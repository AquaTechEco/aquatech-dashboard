import Foundation
import Combine
import CoreLocation

// MARK: - Weather Data Model

struct WatchWeatherData {
    var temperature: Int = 0
    var high: Int = 0
    var low: Int = 0
    var humidity: Int = 0
    var windSpeed: Int = 0
    var windGusts: Int = 0
    var windDirection: String = "--"
    var condition: String = "Loading..."
    var icon: String = "cloud.sun.fill"
    var uvIndex: Int = 0
    var precipChance: Int = 0
    var weatherCode: Int = 0
    var sunrise: String = "--:--"
    var sunset: String = "--:--"
    var waveHeight: Double = 0
    var location: String = "Locating..."
    var lastUpdated: Date = Date()
}

struct NWSAlert {
    let event: String
    let headline: String
    let expires: String
    var isMarine: Bool {
        let evt = event.lowercased()
        return evt.contains("small craft") || evt.contains("gale") || evt.contains("storm warning") || evt.contains("hurricane") || evt.contains("marine") || evt.contains("hazardous seas")
    }
    var isWarning: Bool {
        let evt = event.lowercased()
        return evt.contains("gale") || evt.contains("storm warning") || evt.contains("hurricane")
    }
}

struct TideEvent {
    let type: String  // "H" or "L"
    let time: String
    let height: String
    var isHigh: Bool { type == "H" }
}

struct BoatingRating {
    let text: String      // Good, Caution, Rough, Dangerous
    let color: String     // green, yellow, orange, red
    let description: String

    static func calculate(wind: Int, gusts: Int, waves: Double, wxCode: Int, windDir: String, marineAlerts: [NWSAlert] = []) -> BoatingRating {
        // Check for active NWS marine alerts — these override the calculated rating
        let hasWarning = marineAlerts.contains { $0.isWarning }
        let hasAdvisory = marineAlerts.contains { $0.isMarine }
        if hasWarning { return BoatingRating(text: "Dangerous", color: "red", description: "NWS Warning — stay off the water") }

        var score = hasAdvisory ? 6 : 0 // Advisory ensures at least "Rough"

        // NWS SCA: sustained 25kt (~29mph) or gusts 33kt (~38mph)
        if wind > 29 { score += 4 } else if wind > 20 { score += 3 } else if wind > 15 { score += 2 } else if wind > 10 { score += 1 }
        if gusts > 38 { score += 4 } else if gusts > 30 { score += 3 } else if gusts > 25 { score += 2 } else if gusts > 20 { score += 1 }
        if waves > 6 { score += 4 } else if waves > 4 { score += 3 } else if waves > 3 { score += 2 } else if waves > 2 { score += 1 }
        if [95, 96, 99].contains(wxCode) { score += 4 } else if [61, 63, 65, 80, 82].contains(wxCode) { score += 1 }

        if score <= 2 { return BoatingRating(text: "Good", color: "green", description: "Favorable conditions") }
        if score <= 5 { return BoatingRating(text: "Caution", color: "yellow", description: "Moderate — be aware") }
        if score <= 8 { return BoatingRating(text: "Rough", color: "orange", description: "Small craft caution") }
        return BoatingRating(text: "Dangerous", color: "red", description: "Dangerous — stay off the water")
    }
}

struct TidePoint: Identifiable {
    let id = UUID()
    let date: Date
    let level: Double
}

// MARK: - Location Manager

class LocationDelegate: NSObject, CLLocationManagerDelegate {
    var onLocation: ((CLLocation) -> Void)?
    var onError: (() -> Void)?

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let loc = locations.last {
            onLocation?(loc)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error)")
        onError?()
    }
}

// MARK: - Weather Service

class WeatherService: ObservableObject {
    @Published var weather = WatchWeatherData()
    @Published var tides: [TideEvent] = []
    @Published var tideCurve: [TidePoint] = []
    @Published var alerts: [NWSAlert] = []
    @Published var isLoading = true

    private var lat: Double = 27.9506  // Tampa fallback
    private var lon: Double = -82.4572
    private var tideStation: String = "8726520"
    private var locationName: String = "Tampa, FL"

    // NWS marine zone IDs for Florida locations
    private static let marineZones: [String: [String]] = [
        "Tampa": ["GMZ850", "GMZ856"],
        "St. Petersburg": ["GMZ850", "GMZ856"],
        "Clearwater": ["GMZ850", "GMZ856"],
        "Port St Joe": ["GMZ830", "GMZ835"],
        "Apalachicola": ["GMZ830", "GMZ835"],
        "Key West": ["GMZ042", "AMZ610"],
        "Port St Lucie": ["AMZ550", "AMZ572"],
        "Lake Worth": ["AMZ550", "AMZ572"]
    ]

    private let locationManager = CLLocationManager()
    private let locationDelegate = LocationDelegate()
    private var hasLocation = false

    private var fallbackTimer: Timer?

    init() {
        locationManager.delegate = locationDelegate
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers

        locationDelegate.onLocation = { [weak self] location in
            guard let self = self, !self.hasLocation else { return }
            self.hasLocation = true
            self.lat = location.coordinate.latitude
            self.lon = location.coordinate.longitude
            self.locationManager.stopUpdatingLocation()
            self.fallbackTimer?.invalidate()

            // Reverse geocode for display name
            CLGeocoder().reverseGeocodeLocation(location) { placemarks, _ in
                if let p = placemarks?.first {
                    let name = [p.locality, p.administrativeArea].compactMap { $0 }.joined(separator: ", ")
                    DispatchQueue.main.async {
                        self.weather.location = name.isEmpty ? "Current Location" : name
                    }
                }
            }

            // Find nearest tide station then fetch everything
            self.findNearestTideStation {
                self.fetchWeather()
                self.fetchMarine()
                self.fetchTides()
                self.fetchNWSAlerts()
                // Delay nowcast slightly so it can override weather code if needed
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    self.fetchPrecipNowcast()
                }
            }
        }

        locationDelegate.onError = { [weak self] in
            guard let self = self, !self.hasLocation else { return }
            self.fallbackTimer?.invalidate()
            self.useFallback()
        }
    }

    private func useFallback() {
        hasLocation = true
        weather.location = "Tampa, FL"
        fetchWeather()
        fetchMarine()
        fetchTides()
        fetchNWSAlerts()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.fetchPrecipNowcast()
        }
    }

    func refresh() {
        isLoading = true
        hasLocation = false

        // If location doesn't come in 5 seconds, use Tampa fallback
        fallbackTimer?.invalidate()
        fallbackTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            guard let self = self, !self.hasLocation else { return }
            self.locationManager.stopUpdatingLocation()
            self.useFallback()
        }

        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }

    // MARK: - Find Nearest Tide Station from NOAA

    private func findNearestTideStation(completion: @escaping () -> Void) {
        let pad = 2.0
        let urlStr = "https://api.tidesandcurrents.noaa.gov/mdapi/prod/webapi/stations.json?type=tidepredictions&min_lat=\(lat - pad)&max_lat=\(lat + pad)&min_lon=\(lon - pad)&max_lon=\(lon + pad)"
        guard let url = URL(string: urlStr) else { completion(); return }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let self = self, let data = data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let stations = json["stations"] as? [[String: Any]] else {
                completion()
                return
            }

            // Find closest station by distance
            var bestId = self.tideStation
            var bestDist = Double.greatestFiniteMagnitude
            for s in stations {
                guard let id = s["id"] as? String,
                      let sLat = s["lat"] as? Double,
                      let sLon = s["lng"] as? Double else { continue }
                let dist = hypot(sLat - self.lat, sLon - self.lon)
                if dist < bestDist {
                    bestDist = dist
                    bestId = id
                }
            }
            self.tideStation = bestId
            completion()
        }.resume()
    }

    // MARK: - Fetch Weather

    private func fetchWeather() {
        let urlStr = "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m,wind_gusts_10m&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset,uv_index_max,wind_speed_10m_max,wind_gusts_10m_max,wind_direction_10m_dominant&temperature_unit=fahrenheit&wind_speed_unit=mph&timezone=auto&forecast_days=1"
        guard let url = URL(string: urlStr) else {
            DispatchQueue.main.async { self.isLoading = false }
            return
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let self = self else { return }
            guard let data = data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let current = json["current"] as? [String: Any],
                  let daily = json["daily"] as? [String: Any] else {
                DispatchQueue.main.async { self.isLoading = false }
                return
            }

            let temp = Int((current["temperature_2m"] as? Double) ?? 0)
            let humidity = Int((current["relative_humidity_2m"] as? Double) ?? 0)
            let wxCode = Int((current["weather_code"] as? Double) ?? 0)
            let windNow = Int((current["wind_speed_10m"] as? Double) ?? 0)
            let gustsNow = Int((current["wind_gusts_10m"] as? Double) ?? 0)

            let highs = (daily["temperature_2m_max"] as? [Double]) ?? []
            let lows = (daily["temperature_2m_min"] as? [Double]) ?? []
            let precip = (daily["precipitation_probability_max"] as? [Double]) ?? []
            let uvArr = (daily["uv_index_max"] as? [Double]) ?? []
            let gustsMax = (daily["wind_gusts_10m_max"] as? [Double]) ?? []
            let windDirArr = (daily["wind_direction_10m_dominant"] as? [Double]) ?? []
            let sunriseArr = (daily["sunrise"] as? [String]) ?? []
            let sunsetArr = (daily["sunset"] as? [String]) ?? []

            let (condition, icon) = Self.conditionFromCode(wxCode)
            let windDir = Self.directionFromDegrees(windDirArr.first ?? 0)

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "h:mm a"

            let sunriseStr = sunriseArr.first.flatMap { formatter.date(from: $0) }.map { timeFormatter.string(from: $0) } ?? "--:--"
            let sunsetStr = sunsetArr.first.flatMap { formatter.date(from: $0) }.map { timeFormatter.string(from: $0) } ?? "--:--"

            DispatchQueue.main.async {
                self.weather.temperature = temp
                self.weather.high = Int(highs.first ?? 0)
                self.weather.low = Int(lows.first ?? 0)
                self.weather.humidity = humidity
                self.weather.windSpeed = windNow
                self.weather.windGusts = gustsNow > 0 ? gustsNow : Int(gustsMax.first ?? 0)
                self.weather.windDirection = windDir
                self.weather.condition = condition
                self.weather.icon = icon
                self.weather.uvIndex = Int(uvArr.first ?? 0)
                self.weather.precipChance = Int(precip.first ?? 0)
                self.weather.weatherCode = wxCode
                self.weather.sunrise = sunriseStr
                self.weather.sunset = sunsetStr
                self.weather.lastUpdated = Date()
                self.isLoading = false
            }
        }.resume()
    }

    // MARK: - Fetch Marine

    private func fetchMarine() {
        let today = Self.dateStr(Date())
        // Blend coordinates toward nearest coast for better marine API results
        // Tampa tide station at 27.7606, -82.6269 — blend 60% toward coast
        let stationLat = 27.7606, stationLon = -82.6269
        let marineLat = lat + (stationLat - lat) * 0.6
        let marineLon = lon + (stationLon - lon) * 0.6
        let urlStr = "https://marine-api.open-meteo.com/v1/marine?latitude=\(marineLat)&longitude=\(marineLon)&daily=wave_height_max&timezone=America/New_York&start_date=\(today)&end_date=\(today)"
        guard let url = URL(string: urlStr) else { return }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let data = data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let daily = json["daily"] as? [String: Any],
                  let waves = daily["wave_height_max"] as? [Double],
                  let wh = waves.first else { return }

            DispatchQueue.main.async {
                self?.weather.waveHeight = wh * 3.28084 // meters to feet
            }
        }.resume()
    }

    // MARK: - Fetch Tides

    private func fetchTides() {
        let today = Self.dateStr(Date())
        let tomorrow = Self.dateStr(Date().addingTimeInterval(86400))
        let b = today.replacingOccurrences(of: "-", with: "")
        let e = tomorrow.replacingOccurrences(of: "-", with: "")
        let urlStr = "https://api.tidesandcurrents.noaa.gov/api/prod/datagetter?begin_date=\(b)&end_date=\(e)&station=\(tideStation)&product=predictions&datum=MLLW&time_zone=lst_ldt&interval=hilo&units=english&format=json"
        guard let url = URL(string: urlStr) else { return }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let data = data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let predictions = json["predictions"] as? [[String: Any]] else { return }

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "h:mm a"

            let events = predictions.prefix(6).compactMap { p -> TideEvent? in
                guard let t = p["t"] as? String,
                      let v = p["v"] as? String,
                      let type = p["type"] as? String,
                      let date = formatter.date(from: t) else { return nil }
                let height = String(format: "%.1f ft", Double(v) ?? 0)
                return TideEvent(type: type, time: timeFormatter.string(from: date), height: height)
            }

            DispatchQueue.main.async {
                self?.tides = events
            }
        }.resume()

        // Also fetch hourly for the chart curve
        let hourlyUrlStr = "https://api.tidesandcurrents.noaa.gov/api/prod/datagetter?begin_date=\(b)&end_date=\(e)&station=\(tideStation)&product=predictions&datum=MLLW&time_zone=lst_ldt&interval=h&units=english&format=json"
        guard let hourlyUrl = URL(string: hourlyUrlStr) else { return }

        URLSession.shared.dataTask(with: hourlyUrl) { [weak self] data, _, error in
            guard let data = data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let predictions = json["predictions"] as? [[String: Any]] else { return }

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm"

            let points = predictions.compactMap { p -> TidePoint? in
                guard let t = p["t"] as? String,
                      let v = p["v"] as? String,
                      let date = formatter.date(from: t),
                      let level = Double(v) else { return nil }
                return TidePoint(date: date, level: level)
            }

            DispatchQueue.main.async {
                self?.tideCurve = points
            }
        }.resume()
    }

    // MARK: - Fetch Precipitation Nowcast (cross-reference with current conditions)

    private func fetchPrecipNowcast() {
        let urlStr = "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&minutely_15=precipitation&timezone=auto&forecast_minutely_15=24"
        guard let url = URL(string: urlStr) else { return }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let self = self, let data = data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let minutely = json["minutely_15"] as? [String: Any],
                  let precip = minutely["precipitation"] as? [Double],
                  let times = minutely["time"] as? [String] else { return }

            let now = Date()
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"

            // Check if it's currently raining (recent intervals with precipitation > 0.3mm)
            var isRaining = false
            for i in 0..<precip.count {
                if let t = formatter.date(from: times[i]), t < now, t > now.addingTimeInterval(-900) {
                    if precip[i] > 0.3 { isRaining = true; break }
                }
            }

            // If nowcast says rain but weather code says clear, override condition
            if isRaining {
                DispatchQueue.main.async {
                    if self.weather.weatherCode < 50 {
                        self.weather.condition = "Rain"
                        self.weather.icon = "cloud.rain.fill"
                        self.weather.weatherCode = 61
                    }
                }
            }
        }.resume()
    }

    // MARK: - Fetch NWS Alerts (point + marine zones)

    private func fetchNWSAlerts() {
        // Determine marine zones from location name
        let zones = Self.marineZones.first(where: { weather.location.contains($0.key) })?.value ?? []

        var request = URLRequest(url: URL(string: "https://api.weather.gov/alerts/active?point=\(lat),\(lon)")!)
        request.setValue("AquaTechWeather/1.5", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self else { return }
            var allAlerts: [NWSAlert] = []

            // Parse point-based alerts
            if let data = data, error == nil,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let features = json["features"] as? [[String: Any]] {
                allAlerts.append(contentsOf: Self.parseAlerts(features))
            }

            // Also fetch marine zone alerts if we have zones
            if !zones.isEmpty {
                let zoneStr = zones.joined(separator: ",")
                var zoneRequest = URLRequest(url: URL(string: "https://api.weather.gov/alerts/active?zone=\(zoneStr)")!)
                zoneRequest.setValue("AquaTechWeather/1.5", forHTTPHeaderField: "User-Agent")

                URLSession.shared.dataTask(with: zoneRequest) { data, _, error in
                    if let data = data, error == nil,
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let features = json["features"] as? [[String: Any]] {
                        let zoneAlerts = Self.parseAlerts(features)
                        // Deduplicate by event name
                        let existing = Set(allAlerts.map { $0.event })
                        allAlerts.append(contentsOf: zoneAlerts.filter { !existing.contains($0.event) })
                    }
                    DispatchQueue.main.async {
                        self.alerts = allAlerts
                    }
                }.resume()
            } else {
                DispatchQueue.main.async {
                    self.alerts = allAlerts
                }
            }
        }.resume()
    }

    private static func parseAlerts(_ features: [[String: Any]]) -> [NWSAlert] {
        return features.compactMap { f in
            guard let props = f["properties"] as? [String: Any],
                  let event = props["event"] as? String else { return nil }
            let headline = props["headline"] as? String ?? ""
            let expires = props["expires"] as? String ?? ""
            return NWSAlert(event: event, headline: headline, expires: expires)
        }
    }

    // MARK: - Helpers

    static func dateStr(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    static func directionFromDegrees(_ deg: Double) -> String {
        let dirs = ["N","NNE","NE","ENE","E","ESE","SE","SSE","S","SSW","SW","WSW","W","WNW","NW","NNW"]
        return dirs[Int((deg / 22.5).rounded()) % 16]
    }

    static func conditionFromCode(_ code: Int) -> (String, String) {
        switch code {
        case 0: return ("Clear", "sun.max.fill")
        case 1: return ("Mostly Clear", "sun.min.fill")
        case 2: return ("Partly Cloudy", "cloud.sun.fill")
        case 3: return ("Overcast", "cloud.fill")
        case 45, 48: return ("Foggy", "cloud.fog.fill")
        case 51...57: return ("Drizzle", "cloud.drizzle.fill")
        case 61...67: return ("Rain", "cloud.rain.fill")
        case 71...77: return ("Snow", "cloud.snow.fill")
        case 80...82: return ("Showers", "cloud.sun.rain.fill")
        case 95...99: return ("Thunderstorm", "cloud.bolt.rain.fill")
        default: return ("Unknown", "cloud.fill")
        }
    }
}
