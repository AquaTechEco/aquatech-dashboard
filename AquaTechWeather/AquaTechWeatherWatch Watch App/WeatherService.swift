import Foundation
import Combine

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
    var sunrise: String = "--:--"
    var sunset: String = "--:--"
    var waveHeight: Double = 0
    var location: String = "Tampa, FL"
    var lastUpdated: Date = Date()
}

struct TideEvent {
    let type: String  // "H" or "L"
    let time: String
    let height: String
    var isHigh: Bool { type == "H" }
}

// MARK: - Weather Service

class WeatherService: ObservableObject {
    @Published var weather = WatchWeatherData()
    @Published var tides: [TideEvent] = []
    @Published var isLoading = true

    private let lat = 27.9506
    private let lon = -82.4572
    private let tideStation = "8726520"

    func refresh() {
        isLoading = true
        fetchWeather()
        fetchMarine()
        fetchTides()
    }

    private func fetchWeather() {
        let urlStr = "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset,uv_index_max,wind_speed_10m_max,wind_gusts_10m_max,wind_direction_10m_dominant&temperature_unit=fahrenheit&wind_speed_unit=mph&timezone=America/New_York&forecast_days=1"
        guard let url = URL(string: urlStr) else { return }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let data = data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let current = json["current"] as? [String: Any],
                  let daily = json["daily"] as? [String: Any] else { return }

            let temp = Int((current["temperature_2m"] as? Double) ?? 0)
            let humidity = Int((current["relative_humidity_2m"] as? Double) ?? 0)
            let wxCode = Int((current["weather_code"] as? Double) ?? 0)
            let windNow = Int((current["wind_speed_10m"] as? Double) ?? 0)

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
                self?.weather.temperature = temp
                self?.weather.high = Int(highs.first ?? 0)
                self?.weather.low = Int(lows.first ?? 0)
                self?.weather.humidity = humidity
                self?.weather.windSpeed = windNow
                self?.weather.windGusts = Int(gustsMax.first ?? 0)
                self?.weather.windDirection = windDir
                self?.weather.condition = condition
                self?.weather.icon = icon
                self?.weather.uvIndex = Int(uvArr.first ?? 0)
                self?.weather.precipChance = Int(precip.first ?? 0)
                self?.weather.sunrise = sunriseStr
                self?.weather.sunset = sunsetStr
                self?.weather.lastUpdated = Date()
                self?.isLoading = false
            }
        }.resume()
    }

    private func fetchMarine() {
        let today = Self.dateStr(Date())
        let urlStr = "https://marine-api.open-meteo.com/v1/marine?latitude=\(lat)&longitude=\(lon)&daily=wave_height_max&timezone=America/New_York&start_date=\(today)&end_date=\(today)"
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
