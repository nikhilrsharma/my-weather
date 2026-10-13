import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: WeatherStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showingAddCity = false
    @State private var showingAbout = false
    @State private var cityRowWidth: CGFloat = 0
    @ScaledMetric(relativeTo: .footnote) private var minimumTimelineWidth = 210.0
    @ScaledMetric(relativeTo: .footnote) private var timelineFontSize = 11.0
    @ScaledMetric(relativeTo: .subheadline) private var weatherFontSize = 13.0

    var body: some View {
        NavigationStack {
            TimelineView(.everyMinute) { context in
                let textWidth = store.cities.map { city in
                    let clock = CityClock.text(at: context.date, timezone: city.timezone)
                    return store.snapshots[city.id].map {
                        WeatherSummaryText($0).preferredWidth(clock: clock, fontSize: weatherFontSize)
                    } ?? WeatherBarMetrics.naturalTextWidth([clock], fontSize: weatherFontSize)
                }.max() ?? 120
                let sizing = CityWeatherSizing(
                    rowWidth: cityRowWidth > 0 ? cityRowWidth : 280,
                    preferredTextWidth: max(120, textWidth),
                    minimumTimelineWidth: minimumTimelineWidth,
                    forceStacked: dynamicTypeSize.isAccessibilitySize
                )
                let metrics = WeatherBarMetrics(
                    blocks: store.snapshots.values.flatMap { $0.dayTimeline?.blocks ?? [] },
                    width: sizing.timelineWidth,
                    fontSize: timelineFontSize
                )
                List {
                    Section {
                        if store.cities.isEmpty {
                            Text("No Cities")
                                .font(.weatherBody)
                        } else {
                            ForEach(store.cities) { city in
                                CityRow(
                                    city: city,
                                    snapshot: store.snapshots[city.id],
                                    isUnavailable: store.unavailableCityIDs.contains(city.id),
                                    now: context.date,
                                    sizing: sizing,
                                    metrics: metrics
                                )
                            }
                            .onDelete(perform: store.remove)
                            .onMove(perform: store.move)
                        }
                    } header: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("My Weather")
                                .font(.weatherLargeTitle)
                                .foregroundStyle(Color.primary)
                            Text(lastUpdatedText(store.lastUpdated))
                                .font(.weatherFootnote)
                                .foregroundStyle(Color.secondary)
                        }
                        .textCase(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 6)
                    }
                }
            }
            .onPreferenceChange(CityRowWidthKey.self) { cityRowWidth = $0 }
            .navigationTitle("")
            .weatherInlineNavigationTitle()
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    Button {
                        showingAbout = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .accessibilityLabel("About")

                    #if os(iOS)
                    EditButton()
                        .disabled(store.cities.count < 2)
                    #endif
                }

                ToolbarItemGroup(placement: .primaryAction) {
                    Button("Refresh") {
                        Task { await store.refreshAll() }
                    }
                    .disabled(store.cities.isEmpty || store.isRefreshing)

                    Button("Add") {
                        showingAddCity = true
                    }
                    .disabled(!store.canAddCity || store.isRefreshing)
                }
            }
            .sheet(isPresented: $showingAbout) {
                AboutView(lastUpdated: store.lastUpdated)
            }
            .sheet(isPresented: $showingAddCity) {
                AddCityView()
                    .environmentObject(store)
            }
        }
        .font(.weatherBody)
    }
}

struct CityRow: View {
    let city: SavedCity
    let snapshot: WeatherSnapshot?
    let isUnavailable: Bool
    let now: Date
    let sizing: CityWeatherSizing
    let metrics: WeatherBarMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    cityName
                    currentTemperature
                }
                .fixedSize(horizontal: true, vertical: true)
                VStack(alignment: .leading, spacing: 3) {
                    cityName
                    currentTemperature
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            if let timeline = snapshot?.dayTimeline {
                CityWeatherLayout(sizing: sizing) {
                    weatherText
                        .accessibilitySortPriority(1)
                    DayTimelineView(timeline: timeline, now: now, metrics: metrics)
                }
            } else {
                weatherText
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            GeometryReader { geometry in
                Color.clear.preference(key: CityRowWidthKey.self, value: geometry.size.width)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var cityName: some View {
        Text(city.name).font(.weatherHeadline)
    }

    @ViewBuilder
    private var currentTemperature: some View {
        if let snapshot {
            Text(WeatherSummaryText(snapshot).current)
                .font(.weatherSubheadline)
                .monospacedDigit()
                .accessibilityLabel("Current Temperature: \(wholeDegrees(snapshot.current.temperature))")
        }
    }

    private var cityClock: some View {
        Text(CityClock.text(at: now, timezone: city.timezone))
            .font(.weatherFootnote)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel("Current Local Time: \(CityClock.text(at: now, timezone: city.timezone)), \(city.timezone)")
    }

    private var weatherText: some View {
        VStack(alignment: .leading, spacing: 5) {
            cityClock
            if let snapshot {
                let summary = WeatherSummaryText(snapshot)
                Text(summary.lowHigh)
                    .font(.weatherSubheadline)

                DailyConditionRow(humidity: summary.humidity, condition: snapshot.today.condition)

                Text(summary.precipitation)
                    .font(.weatherSubheadline)
                    .foregroundStyle(.secondary)
            } else if isUnavailable {
                Text("Unavailable")
                    .font(.weatherSubheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct WeatherSummaryText {
    let current: String
    let lowHigh: String
    let humidity: String
    let condition: String
    let precipitation: String

    func preferredWidth(clock: String, fontSize: CGFloat) -> CGFloat {
        let plainWidth = WeatherBarMetrics.naturalTextWidth([clock, lowHigh, precipitation], fontSize: fontSize)
        let badgeRowWidth = WeatherBarMetrics.naturalTextWidth([humidity + " ·"], fontSize: fontSize)
            + DailyConditionRow.spacing
            + WeatherBarMetrics.naturalTextWidth([condition], fontSize: fontSize)
            + 2 * DailyConditionBadge.horizontalInset
        return max(plainWidth, badgeRowWidth) + 2 // Text rounding allowance.
    }

    init(_ snapshot: WeatherSnapshot) {
        current = wholeDegrees(snapshot.current.temperature)
        lowHigh = "Low \(wholeDegrees(snapshot.today.minimumTemperature)) · High \(wholeDegrees(snapshot.today.maximumTemperature))"
        humidity = "Humidity \(snapshot.current.humidity)%"
        condition = snapshot.today.condition.rawValue
        precipitation = snapshot.today.precipitation.label
    }
}

/// Keep the fourth line inline when it fits; otherwise give the full condition
/// its own line rather than truncating it or shrinking the user's chosen font.
struct DailyConditionRow: View {
    static let spacing: CGFloat = 5
    let humidity: String
    let condition: WholeDayCondition

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: Self.spacing) {
                Text(humidity + " ·").foregroundStyle(.secondary)
                DailyConditionBadge(condition: condition)
            }
            .fixedSize(horizontal: true, vertical: true)
            VStack(alignment: .leading, spacing: 4) {
                Text(humidity).foregroundStyle(.secondary)
                DailyConditionBadge(condition: condition)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .font(.weatherSubheadline)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(humidity), \(condition.rawValue)")
    }
}

struct DailyConditionBadge: View {
    static let horizontalInset: CGFloat = 8
    let condition: WholeDayCondition

    var body: some View {
        let palette = DailyConditionPalette(condition)
        Text(condition.rawValue)
            .font(.weatherSubheadline)
            .foregroundStyle(palette.foreground)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Self.horizontalInset)
            .padding(.vertical, 3)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(palette.background)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(palette.border, lineWidth: 1)
            }
    }
}

/// Opaque, dark-mode colors keep contrast predictable. Meaning is always
/// conveyed by the full condition label as well as by the weather-color family.
struct DailyConditionPalette: Equatable {
    let foregroundHex: UInt32
    let backgroundHex: UInt32
    let borderHex: UInt32

    init(_ condition: WholeDayCondition) {
        let values: (UInt32, UInt32, UInt32)
        switch condition {
        case .sunny: values = (0xFFD87A, 0x483611, 0xC9A345)
        case .sunCloudMix: values = (0xFFE4A6, 0x414039, 0xBBA879)
        case .cloudy: values = (0xE1E7EF, 0x363E4B, 0x8D9BAF)
        case .fog: values = (0xD5EFEA, 0x2C4543, 0x8AB6AC)
        case .drizzle: values = (0xD0EFF8, 0x214451, 0x78B8CD)
        case .rain, .showers: values = (0xD9EAFE, 0x253D57, 0x7AABD7)
        case .freezingDrizzle, .freezingRain: values = (0xDDE4FF, 0x354058, 0x9CAEE0)
        case .snow, .snowShowers: values = (0xDCF5FF, 0x2D4652, 0x92C8DA)
        case .thunderstorm: values = (0xEEDDFF, 0x473656, 0xBE9AD6)
        case .unknown: values = (0xE8E8EE, 0x3D3D44, 0xACABB8)
        }
        (foregroundHex, backgroundHex, borderHex) = values
    }

    var foreground: Color { Self.color(foregroundHex) }
    var background: Color { Self.color(backgroundHex) }
    var border: Color { Self.color(borderHex) }

    private static func color(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255,
              green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255)
    }
}

private struct CityRowWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        guard next > 0 else { return }
        value = value > 0 ? min(value, next) : next
    }
}

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    let lastUpdated: Date?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Nikhil Sharma")
                        .font(.weatherHeadline)

                    Text("Built with help from ChatGPT models.")
                        .font(.weatherBody)

                    Divider()

                    Text(lastUpdatedText(lastUpdated))
                        .font(.weatherSubheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .navigationTitle("")
            .weatherInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("About")
                        .font(.weatherHeadline)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .font(.weatherBody)
    }
}

private let lastUpdatedDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = .autoupdatingCurrent
    formatter.timeZone = .autoupdatingCurrent
    formatter.setLocalizedDateFormatFromTemplate("yMMMdjm")
    return formatter
}()

func lastUpdatedText(_ date: Date?) -> String {
    guard let date else { return "Last Updated: Not Yet" }

    let timeZone = TimeZone.autoupdatingCurrent.abbreviation(for: date)
    let suffix = timeZone.map { " \($0)" } ?? ""
    return "Last Updated: \(lastUpdatedDateFormatter.string(from: date))\(suffix)"
}

func wholeDegrees(_ value: Double) -> String {
    "\(Int(value.rounded()))°C"
}
