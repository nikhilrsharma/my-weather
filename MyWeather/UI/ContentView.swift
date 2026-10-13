import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: WeatherStore
    @State private var showingAddCity = false
    @State private var showingAbout = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("My Weather")
                        .font(.weatherLargeTitle)

                    Text(lastUpdatedText(store.lastUpdated))
                        .font(.weatherFootnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 6)

                if store.cities.isEmpty {
                    Spacer()
                    HStack {
                        Spacer()
                        Text("No Cities")
                            .font(.weatherBody)
                        Spacer()
                    }
                    Spacer()
                } else {
                    List {
                        ForEach(store.cities) { city in
                            CityRow(
                                city: city,
                                snapshot: store.snapshots[city.id],
                                isUnavailable: store.unavailableCityIDs.contains(city.id)
                            )
                        }
                        .onDelete(perform: store.remove)
                        .onMove(perform: store.move)
                    }
                }
            }
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

private struct CityRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .footnote) private var timelineWidth = 154.0
    let city: SavedCity
    let snapshot: WeatherSnapshot?
    let isUnavailable: Bool

    var body: some View {
        Group {
            if let timeline = snapshot?.dayTimeline {
                CityWeatherLayout(timelineWidth: timelineWidth, stackVertically: dynamicTypeSize > .xLarge) {
                    weatherText
                        .accessibilitySortPriority(1)
                    DayTimelineView(timeline: timeline)
                }
            } else {
                weatherText
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }

    private var weatherText: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(city.name)
                .font(.weatherHeadline)

            if let snapshot {
                Text(wholeDegrees(snapshot.current.temperature))
                    .font(.weatherSubheadline)

                Text(
                    "Low \(wholeDegrees(snapshot.today.minimumTemperature)) · " +
                    "High \(wholeDegrees(snapshot.today.maximumTemperature))"
                )
                .font(.weatherSubheadline)

                Text(
                    "Humidity \(snapshot.current.humidity)% · " +
                    snapshot.today.condition.rawValue
                )
                    .font(.weatherSubheadline)
                    .foregroundStyle(.secondary)

                Text(snapshot.today.precipitation.label)
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

private struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    let lastUpdated: Date?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Nikhil Sharma")
                    .font(.weatherHeadline)

                Text("Built with help from ChatGPT models.")
                    .font(.weatherBody)

                Divider()

                Text(lastUpdatedText(lastUpdated))
                    .font(.weatherSubheadline)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
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
