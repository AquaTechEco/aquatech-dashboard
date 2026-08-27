import WidgetKit
import SwiftUI

// MARK: - Simple Entry

struct SimpleEntry: TimelineEntry {
    let date: Date
    let temperature: Int
    let high: Int
    let low: Int
    let condition: String
    let icon: String
    let location: String
    let humidity: Int
    let windSpeed: Int

    static let placeholder = SimpleEntry(
        date: Date(),
        temperature: 72,
        high: 78,
        low: 65,
        condition: "Partly Cloudy",
        icon: "cloud.sun.fill",
        location: "Tampa, FL",
        humidity: 65,
        windSpeed: 8
    )
}

// MARK: - Provider

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry.placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        if context.isPreview {
            completion(SimpleEntry.placeholder)
            return
        }
        fetchWeather { entry in
            completion(entry)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> ()) {
        fetchWeather { entry in
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
            completion(timeline)
        }
    }

    private static let nwsUA = "AquaTechWeather/1.6 (contact: beau@aquatecheco.com)"

    private func fetchWeather(completion: @escaping (SimpleEntry) -> Void) {
        // TODO(location): still defaults to Tampa. Live widget location needs a shared
        // App Group (the container app writes its last CLLocation; the widget reads it) —
        // a capability/signing change, tracked as a follow-up.
        let lat = 27.9506
        let lon = -82.4572
        let locationName = "Tampa, FL"

        guard let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m&daily=temperature_2m_max,temperature_2m_min&temperature_unit=fahrenheit&wind_speed_unit=mph&timezone=America/New_York") else {
            completion(SimpleEntry.placeholder)
            return
        }

        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil else {
                completion(SimpleEntry.placeholder)
                return
            }

            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let current = json["current"] as? [String: Any],
                      let daily = json["daily"] as? [String: Any] else {
                    completion(SimpleEntry.placeholder)
                    return
                }

                let temp = (current["temperature_2m"] as? Double) ?? 72.0
                let humidityVal = (current["relative_humidity_2m"] as? Double) ?? 65.0
                let windSpeedVal = (current["wind_speed_10m"] as? Double) ?? 8.0
                let weatherCode = (current["weather_code"] as? Int) ?? ((current["weather_code"] as? Double).map { Int($0) } ?? 0)

                let highs = daily["temperature_2m_max"] as? [Double] ?? [78]
                let lows = daily["temperature_2m_min"] as? [Double] ?? [65]

                // Overlay NWS MEASURED obs on the Open-Meteo baseline so the widget matches
                // the dashboard / Watch (measured wins). Falls back to the model on failure.
                self.fetchNWSMeasured(lat: lat, lon: lon) { m in
                    let entry = SimpleEntry(
                        date: Date(),
                        temperature: m?.temp ?? Int(temp),
                        high: Int(highs.first ?? 78),
                        low: Int(lows.first ?? 65),
                        condition: conditionForCode(weatherCode),
                        icon: iconForCode(weatherCode),
                        location: locationName,
                        humidity: m?.humidity ?? Int(humidityVal),
                        windSpeed: m?.wind ?? Int(windSpeedVal)
                    )
                    completion(entry)
                }
            } catch {
                completion(SimpleEntry.placeholder)
            }
        }
        task.resume()
    }

    struct NWSMeasured { let temp: Int?; let humidity: Int?; let wind: Int? }

    /// Latest measured NWS observation, walking the nearest few stations to skip partial
    /// (null-value) reporters. Mirrors the ATEC Daily Log / dashboard / Watch overlay.
    private func fetchNWSMeasured(lat: Double, lon: Double, completion: @escaping (NWSMeasured?) -> Void) {
        func req(_ s: String) -> URLRequest? {
            guard let u = URL(string: s) else { return nil }
            var r = URLRequest(url: u); r.setValue(Self.nwsUA, forHTTPHeaderField: "User-Agent"); return r
        }
        guard let pReq = req("https://api.weather.gov/points/\(String(format: "%.4f", lat)),\(String(format: "%.4f", lon))") else { completion(nil); return }
        URLSession.shared.dataTask(with: pReq) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let props = json["properties"] as? [String: Any],
                  let stationsURL = props["observationStations"] as? String,
                  let sReq = req(stationsURL) else { completion(nil); return }
            URLSession.shared.dataTask(with: sReq) { sdata, _, _ in
                guard let sdata = sdata,
                      let sjson = try? JSONSerialization.jsonObject(with: sdata) as? [String: Any],
                      let features = sjson["features"] as? [[String: Any]] else { completion(nil); return }
                let ids = features.compactMap { ($0["properties"] as? [String: Any])?["stationIdentifier"] as? String }
                func walk(_ i: Int) {
                    guard i < ids.count, i < 4, let oReq = req("https://api.weather.gov/stations/\(ids[i])/observations/latest") else { completion(nil); return }
                    URLSession.shared.dataTask(with: oReq) { odata, _, _ in
                        guard let odata = odata,
                              let ojson = try? JSONSerialization.jsonObject(with: odata) as? [String: Any],
                              let o = ojson["properties"] as? [String: Any],
                              let tf = o["temperature"] as? [String: Any],
                              let tc = tf["value"] as? Double else { walk(i + 1); return }
                        if let ts = o["timestamp"] as? String, let d = ISO8601DateFormatter().date(from: ts), Date().timeIntervalSince(d) > 2 * 3600 { walk(i + 1); return }
                        func mph(_ field: Any?) -> Int? {
                            guard let f = field as? [String: Any], let v = f["value"] as? Double else { return nil }
                            let u = f["unitCode"] as? String ?? ""
                            if u == "wmoUnit:km_h-1" { return Int((v * 0.621371).rounded()) }
                            if u == "wmoUnit:m_s-1" { return Int((v * 2.23694).rounded()) }
                            return Int(v.rounded())
                        }
                        let hum = (o["relativeHumidity"] as? [String: Any])?["value"] as? Double
                        completion(NWSMeasured(temp: Int((tc * 9/5 + 32).rounded()), humidity: hum.map { Int($0.rounded()) }, wind: mph(o["windSpeed"])))
                    }.resume()
                }
                walk(0)
            }.resume()
        }.resume()
    }

    func iconForCode(_ code: Int) -> String {
        switch code {
        case 0: return "sun.max.fill"
        case 1, 2: return "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55, 56, 57: return "cloud.drizzle.fill"
        case 61, 63, 65, 66, 67, 80, 81, 82: return "cloud.rain.fill"
        case 95, 96, 99: return "cloud.bolt.fill"
        default: return "cloud.sun.fill"
        }
    }

    func conditionForCode(_ code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1: return "Mostly Clear"
        case 2: return "Partly Cloudy"
        case 3: return "Overcast"
        case 45, 48: return "Foggy"
        case 51, 53, 55: return "Drizzle"
        case 56, 57: return "Freezing Drizzle"
        case 61, 63, 65: return "Rain"
        case 66, 67: return "Freezing Rain"
        case 80, 81, 82: return "Showers"
        case 95: return "Thunderstorm"
        case 96, 99: return "Severe Storm"
        default: return "Unknown"
        }
    }
}

// MARK: - Widget Views

struct SmallWidgetView: View {
    let entry: SimpleEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: entry.icon)
                    .font(.title2)
                    .foregroundStyle(.yellow)
                Spacer()
            }

            Text("\(entry.temperature)°")
                .font(.system(size: 42, weight: .bold))
                .foregroundStyle(.white)

            Text(entry.condition)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.9))

            Spacer()

            Text(entry.location)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding()
    }
}

struct MediumWidgetView: View {
    let entry: SimpleEntry

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: entry.icon)
                        .font(.title)
                        .foregroundStyle(.yellow)
                    Spacer()
                }

                Text("\(entry.temperature)°")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(.white)

                Text(entry.condition)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))

                Spacer()

                Text(entry.location)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                DetailRow(icon: "arrow.up", value: "\(entry.high)°")
                DetailRow(icon: "arrow.down", value: "\(entry.low)°")
                DetailRow(icon: "humidity.fill", value: "\(entry.humidity)%")
                DetailRow(icon: "wind", value: "\(entry.windSpeed) mph")
            }
        }
        .padding()
    }
}

struct DetailRow: View {
    let icon: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
        }
    }
}

struct LargeWidgetView: View {
    let entry: SimpleEntry

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text(entry.location)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("AquaTech Weather")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                Image(systemName: entry.icon)
                    .font(.largeTitle)
                    .foregroundStyle(.yellow)
            }

            HStack(alignment: .top) {
                Text("\(entry.temperature)")
                    .font(.system(size: 72, weight: .bold))
                    .foregroundStyle(.white)
                Text("°F")
                    .font(.title)
                    .foregroundStyle(.white.opacity(0.8))
                    .offset(y: 8)

                Spacer()

                VStack(alignment: .trailing) {
                    Text("H: \(entry.high)°")
                        .foregroundStyle(.white)
                    Text("L: \(entry.low)°")
                        .foregroundStyle(.white.opacity(0.8))
                }
                .font(.title3)
            }

            Text(entry.condition)
                .font(.title3)
                .foregroundStyle(.white.opacity(0.9))

            Spacer()

            HStack(spacing: 20) {
                LargeDetailItem(icon: "humidity.fill", label: "Humidity", value: "\(entry.humidity)%")
                LargeDetailItem(icon: "wind", label: "Wind", value: "\(entry.windSpeed) mph")
                LargeDetailItem(icon: "clock", label: "Updated", value: formatTime(entry.date))
            }

            Text("Tap to open full dashboard →")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding()
    }

    func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct LargeDetailItem: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.white.opacity(0.8))
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Widget Entry View

struct AquaTechWeatherWidgetEntryView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family

    private var gradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.1, green: 0.32, blue: 0.46),
                Color(red: 0.18, green: 0.53, blue: 0.67),
                Color(red: 0.28, green: 0.72, blue: 0.63)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(entry: entry)
        case .systemMedium:
            MediumWidgetView(entry: entry)
        case .systemLarge:
            LargeWidgetView(entry: entry)
        default:
            SmallWidgetView(entry: entry)
        }
    }

    var body: some View {
        if #available(iOSApplicationExtension 17.0, *) {
            content
                .containerBackground(for: .widget) {
                    gradient
                }
        } else {
            ZStack {
                gradient
                content
            }
        }
    }
}

// MARK: - Widget Configuration

struct AquaTechWeatherWidget: Widget {
    let kind: String = "AquaTechWeatherWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            AquaTechWeatherWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("AquaTech Weather")
        .description("Current weather conditions from your AquaTech dashboard.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Previews

struct AquaTechWeatherWidget_Previews: PreviewProvider {
    static var previews: some View {
        AquaTechWeatherWidgetEntryView(entry: SimpleEntry.placeholder)
            .previewContext(WidgetPreviewContext(family: .systemSmall))
        AquaTechWeatherWidgetEntryView(entry: SimpleEntry.placeholder)
            .previewContext(WidgetPreviewContext(family: .systemMedium))
        AquaTechWeatherWidgetEntryView(entry: SimpleEntry.placeholder)
            .previewContext(WidgetPreviewContext(family: .systemLarge))
    }
}
