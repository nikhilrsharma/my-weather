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
            let textWidth = WeatherBarMetrics.naturalTextWidth(
                store.snapshots.values.flatMap { WeatherSummaryText($0).lines }, fontSize: weatherFontSize
            ) + 2 // Small rounding allowance keeps complete weather lines together.
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
            TimelineView(.everyMinute) { context in
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
                    cityClock
                }
                .fixedSize(horizontal: true, vertical: true)
                VStack(alignment: .leading, spacing: 3) {
                    cityName
                    cityClock
                }
                .fixedSize(horizontal: false, vertical: true)
            }
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
            if let snapshot {
                let summary = WeatherSummaryText(snapshot)
                Text(summary.current)
                    .font(.weatherSubheadline)

                Text(summary.lowHigh)
                .font(.weatherSubheadline)

                Text(summary.humidityCondition)
                    .font(.weatherSubheadline)
                    .foregroundStyle(.secondary)

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
    let humidityCondition: String
    let precipitation: String
    var lines: [String] { [current, lowHigh, humidityCondition, precipitation] }

    init(_ snapshot: WeatherSnapshot) {
        current = wholeDegrees(snapshot.current.temperature)
        lowHigh = "Low \(wholeDegrees(snapshot.today.minimumTemperature)) · High \(wholeDegrees(snapshot.today.maximumTemperature))"
        humidityCondition = "Humidity \(snapshot.current.humidity)% · \(snapshot.today.condition.rawValue)"
        precipitation = snapshot.today.precipitation.label
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
