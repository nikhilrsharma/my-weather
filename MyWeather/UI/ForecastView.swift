import SwiftUI

enum WeatherScreen: String, CaseIterable {
    case today, forecast
    var label: String { self == .today ? "Today" : "5-Day Forecast" }
}

/// The approved compact switch: unchanged 48-by-44 selection, with the app's
/// actual icon inside it. Selection changes only the view, never the cache.
struct WeatherViewSwitch: View {
    let screen: WeatherScreen
    let select: (WeatherScreen) -> Void
    @ScaledMetric(relativeTo: .footnote) private var labelFontSize = 11.0

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 0) {
                ForEach(WeatherScreen.allCases, id: \.self) { destination in
                    Button { select(destination) } label: {
                        Group {
                            if destination == .today {
                                Image("TodayIcon")
                                    .resizable().scaledToFit()
                                    .frame(width: 36, height: 36)
                                    .clipShape(Circle())
                            } else {
                                Image(systemName: "calendar")
                                    .font(.system(size: 20, weight: .regular))
                                    .foregroundStyle(screen == .forecast ? Color(white: 0.11) : Color(white: 0.71))
                            }
                        }
                        .frame(width: 48, height: 44)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(destination.label)
                    .accessibilityIdentifier("weather-view-\(destination.rawValue)")
                    .accessibilityAddTraits(screen == destination ? .isSelected : [])
                }
            }
            .background(alignment: .leading) {
                Capsule().fill(Color(white: 0.93)).frame(width: 48, height: 44)
                    .offset(x: screen == .forecast ? 48 : 0)
                    .accessibilityHidden(true)
            }
            .padding(4)
            .background(Capsule().fill(Color(white: 0.13)))
            Text(screen.label)
                .font(.weatherFootnote)
                .foregroundStyle(Color(white: 0.72))
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center)
                .accessibilityHidden(true)
        }
        // Keep both icon targets unchanged, but give the caption enough room
        // at accessibility sizes instead of breaking a word into fragments.
        .frame(width: max(104, WeatherBarMetrics.naturalTextWidth(
            WeatherScreen.allCases.map(\.label), fontSize: labelFontSize) + 4))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Weather View")
    }
}

struct ForecastCityView: View {
    let city: SavedCity
    let snapshot: WeatherSnapshot?
    let now: Date
    let temperatureWidth: CGFloat
    let rowWidth: CGFloat
    private var stacksTemperatures: Bool { rowWidth < temperatureWidth * 2 + 136 }

    var body: some View {
        if let snapshot, let days = snapshot.forecastDays, !days.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                ForecastTimeAxis(timeline: nil, temperatureWidth: temperatureWidth, stacked: stacksTemperatures)
                ForEach(days) { day in
                    ForecastDayRow(
                        day: day, timezone: city.timezone, now: now,
                        currentTemperature: day.id == days.first?.id && day.isToday(at: now, timezone: city.timezone)
                            ? snapshot.current.temperature : nil,
                        temperatureWidth: temperatureWidth, stacksTemperatures: stacksTemperatures
                    )
                }
                if days.count < 5 {
                    Text("More Days Unavailable. Refresh on Today.")
                        .font(.weatherFootnote).foregroundStyle(.secondary)
                }
            }
        } else {
            Text("Refresh on Today to Load the 5-Day Forecast.")
                .font(.weatherSubheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct ForecastDayRow: View {
    let day: DailyForecast
    let timezone: String
    let now: Date
    let currentTemperature: Double?
    let temperatureWidth: CGFloat
    var stacksTemperatures = false

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    dateLabel.fixedSize(horizontal: true, vertical: true)
                    Spacer(minLength: 4)
                    DailyConditionBadge(condition: day.weather.condition, compact: true)
                        .fixedSize(horizontal: true, vertical: true)
                }
                VStack(alignment: .leading, spacing: 3) {
                    dateLabel
                    DailyConditionBadge(condition: day.weather.condition, compact: true)
                }
            }
            // On daylight-saving transition days, place the actual day's clock
            // ticks next to its bar instead of applying a 24-hour axis to it.
            if let timeline = day.timeline,
               let start = timeline.detailedBlocks.first?.start,
               let end = timeline.detailedBlocks.last?.end,
               end.timeIntervalSince(start) != 86_400 {
                ForecastTimeAxis(timeline: timeline, temperatureWidth: temperatureWidth, stacked: stacksTemperatures)
            }
            if stacksTemperatures {
                HStack { minimum; Spacer(); maximum }
                ForecastWeatherBar(timeline: day.timeline, now: now, currentTemperature: currentTemperature)
            } else {
                HStack(alignment: .bottom, spacing: 8) {
                    minimum.frame(width: temperatureWidth, alignment: .leading).padding(.bottom, 1)
                    ForecastWeatherBar(timeline: day.timeline, now: now, currentTemperature: currentTemperature)
                    maximum.frame(width: temperatureWidth, alignment: .trailing).padding(.bottom, 1)
                }
            }
            if day.timeline == nil {
                Text("Hourly Unavailable").font(.weatherFootnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibleSummary)
    }

    private var minimum: some View {
        Text(degrees(day.weather.minimumTemperature)).font(.weatherSubheadline)
            .monospacedDigit().foregroundStyle(.secondary)
    }

    private var maximum: some View {
        Text(degrees(day.weather.maximumTemperature)).font(.weatherSubheadline).monospacedDigit()
    }

    private var dateLabel: some View {
        let components = dateComponents
        return HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(day.isToday(at: now, timezone: timezone) ? "Today" : components.weekday)
                .font(.weatherFootnote).bold()
            Text(components.date).font(.weatherFootnote).foregroundStyle(.secondary)
        }
    }

    private var dateComponents: (weekday: String, date: String) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timezone) ?? TimeZone(secondsFromGMT: 0)!
        let parts = calendar.dateComponents([.weekday, .day, .month], from: day.date)
        let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return (weekdays[(parts.weekday ?? 1) - 1], "\(parts.day ?? 1) \(months[(parts.month ?? 1) - 1])")
    }

    private var accessibleSummary: String {
        let current = currentTemperature.map { ", Current Temperature \(wholeDegrees($0))" } ?? ""
        let periods = day.timeline?.detailedBlocks.map { "\($0.accessibleTimeLabel), \($0.label)" }.joined(separator: "; ")
            ?? "Hourly Weather Unavailable"
        return "\(dateComponents.weekday) \(dateComponents.date), \(day.weather.condition.rawValue), Minimum \(wholeDegrees(day.weather.minimumTemperature)), Maximum \(wholeDegrees(day.weather.maximumTemperature))\(current). \(periods)"
    }
}

private struct ForecastTimeAxis: View {
    let timeline: DayTimeline?
    let temperatureWidth: CGFloat
    var stacked = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .footnote) private var height = 17.0
    @ScaledMetric(relativeTo: .footnote) private var inset = 9.0

    var body: some View {
        HStack(spacing: stacked ? 0 : 8) {
            Color.clear.frame(width: stacked ? 0 : temperatureWidth, height: 1)
            GeometryReader { geometry in
                ForEach(dynamicTypeSize.isAccessibilitySize ? [0, 12, 24] : [0, 6, 12, 18, 24], id: \.self) { hour in
                    Text(String(format: "%02d", hour))
                        .font(.weatherFootnote).foregroundStyle(.secondary)
                        .fixedSize()
                        .position(x: min(max(inset, geometry.size.width * position(for: hour)), max(inset, geometry.size.width - inset)), y: geometry.size.height / 2)
                }
            }
            Color.clear.frame(width: stacked ? 0 : temperatureWidth, height: 1)
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    private func position(for hour: Int) -> Double {
        guard hour > 0, hour < 24, let timeline,
              let start = timeline.detailedBlocks.first?.start,
              let timezone = TimeZone(identifier: timeline.timezone) else { return Double(hour) / 24 }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        guard let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: start) else { return Double(hour) / 24 }
        return timeline.position(at: date) ?? Double(hour) / 24
    }
}

struct ForecastWeatherBar: View {
    let timeline: DayTimeline?
    let now: Date
    let currentTemperature: Double?
    @ScaledMetric(relativeTo: .footnote) private var labelHeight = 16.0
    @ScaledMetric(relativeTo: .footnote) private var labelFontSize = 11.0
    private var topInset: CGFloat { currentTemperature == nil ? 0 : labelHeight }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                if let timeline, !timeline.gradientStops.isEmpty {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(LinearGradient(stops: timeline.gradientStops.map {
                            Gradient.Stop(color: color($0.color), location: $0.location)
                        }, startPoint: .leading, endPoint: .trailing))
                        .frame(height: 14).offset(y: topInset + 2)
                    if let temperature = currentTemperature, let position = timeline.position(at: now) {
                        let x = geometry.size.width * position
                        let labelWidth = min(geometry.size.width, WeatherBarMetrics.naturalTextWidth([degrees(temperature)], fontSize: labelFontSize) + 4)
                        Text(degrees(temperature)).font(.weatherFootnote).monospacedDigit()
                            .frame(width: labelWidth, height: labelHeight)
                            .position(x: min(max(labelWidth / 2, x), geometry.size.width - labelWidth / 2), y: labelHeight / 2)
                        Circle().fill(Color(red: 1, green: 0.23, blue: 0.19))
                            .overlay { Circle().strokeBorder(.white, lineWidth: 1.5) }
                            .frame(width: 9, height: 9)
                            .position(x: min(max(4.5, x), max(4.5, geometry.size.width - 4.5)), y: topInset + 9)
                    }
                } else {
                    RoundedRectangle(cornerRadius: 7).fill(Color(white: 0.26))
                        .frame(height: 14).offset(y: topInset + 2)
                    if let temperature = currentTemperature {
                        Text(degrees(temperature)).font(.weatherFootnote).monospacedDigit()
                            .frame(width: geometry.size.width, height: labelHeight)
                    }
                }
            }
        }
        .frame(height: topInset + 16)
        .accessibilityHidden(true)
    }

    private func color(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255,
              green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

private func degrees(_ value: Double) -> String {
    "\(Int(value.rounded()))°"
}
