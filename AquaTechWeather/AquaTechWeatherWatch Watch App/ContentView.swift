import SwiftUI

struct ContentView: View {
    @StateObject private var service = WeatherService()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    // Current conditions hero
                    currentConditions

                    // Quick stats row
                    quickStats

                    // Tide section
                    tideSection

                    // Wind section
                    windSection

                    // Marine section
                    marineSection

                    // Sun section
                    sunSection

                    // Last updated
                    Text("Updated \(service.weather.lastUpdated, style: .time)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 4)
            }
            .navigationTitle("ATEC Weather")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear { service.refresh() }
    }

    // MARK: - Current Conditions

    private var currentConditions: some View {
        VStack(spacing: 2) {
            Image(systemName: service.weather.icon)
                .font(.system(size: 36))
                .symbolRenderingMode(.multicolor)

            Text("\(service.weather.temperature)°")
                .font(.system(size: 44, weight: .bold, design: .rounded))

            Text(service.weather.condition)
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                Label("H: \(service.weather.high)°", systemImage: "arrow.up")
                    .font(.caption2)
                    .foregroundColor(.orange)
                Label("L: \(service.weather.low)°", systemImage: "arrow.down")
                    .font(.caption2)
                    .foregroundColor(.cyan)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Quick Stats

    private var quickStats: some View {
        HStack(spacing: 0) {
            statItem(icon: "drop.fill", value: "\(service.weather.precipChance)%", label: "Rain", color: .blue)
            Divider().frame(height: 30)
            statItem(icon: "humidity.fill", value: "\(service.weather.humidity)%", label: "Humid", color: .teal)
            Divider().frame(height: 30)
            statItem(icon: "sun.max.fill", value: "\(service.weather.uvIndex)", label: "UV", color: .yellow)
        }
        .padding(8)
        .background(Color.white.opacity(0.08))
        .cornerRadius(12)
    }

    private func statItem(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)
            Text(value)
                .font(.system(.caption, design: .rounded, weight: .bold))
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Tides

    private var tideSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Tides", systemImage: "water.waves")
                .font(.caption.bold())
                .foregroundColor(.cyan)

            if service.tides.isEmpty {
                Text("Loading tides...")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                ForEach(Array(service.tides.prefix(4).enumerated()), id: \.offset) { _, tide in
                    HStack {
                        Circle()
                            .fill(tide.isHigh ? Color.green : Color.orange)
                            .frame(width: 6, height: 6)
                        Text(tide.isHigh ? "High" : "Low")
                            .font(.caption2.bold())
                            .frame(width: 30, alignment: .leading)
                        Text(tide.time)
                            .font(.system(.caption2, design: .monospaced))
                        Spacer()
                        Text(tide.height)
                            .font(.caption2.bold())
                    }
                    .padding(.vertical, 1)
                }
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.08))
        .cornerRadius(12)
    }

    // MARK: - Wind

    private var windSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Wind", systemImage: "wind")
                .font(.caption.bold())
                .foregroundColor(.mint)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(service.weather.windSpeed)")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                        Text("mph")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Text(service.weather.windDirection)
                        .font(.caption.bold())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Gusts")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    Text("\(service.weather.windGusts) mph")
                        .font(.caption.bold())
                        .foregroundColor(service.weather.windGusts > 20 ? .red : .primary)
                }
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.08))
        .cornerRadius(12)
    }

    // MARK: - Marine

    private var marineSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Marine", systemImage: "sailboat.fill")
                .font(.caption.bold())
                .foregroundColor(.blue)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Waves")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    Text(String(format: "%.1f ft", service.weather.waveHeight))
                        .font(.caption.bold())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Clarity")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    Text(service.weather.waveHeight < 2 ? "Good" : service.weather.waveHeight < 4 ? "Moderate" : "Poor")
                        .font(.caption.bold())
                        .foregroundColor(service.weather.waveHeight < 2 ? .green : service.weather.waveHeight < 4 ? .yellow : .red)
                }
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.08))
        .cornerRadius(12)
    }

    // MARK: - Sun

    private var sunSection: some View {
        HStack {
            VStack(spacing: 2) {
                Image(systemName: "sunrise.fill")
                    .foregroundColor(.orange)
                    .font(.caption)
                Text(service.weather.sunrise)
                    .font(.system(.caption2, design: .monospaced, weight: .bold))
                Text("Rise")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)

            Divider().frame(height: 30)

            VStack(spacing: 2) {
                Image(systemName: "sunset.fill")
                    .foregroundColor(.pink)
                    .font(.caption)
                Text(service.weather.sunset)
                    .font(.system(.caption2, design: .monospaced, weight: .bold))
                Text("Set")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(8)
        .background(Color.white.opacity(0.08))
        .cornerRadius(12)
    }
}

#Preview {
    ContentView()
}
