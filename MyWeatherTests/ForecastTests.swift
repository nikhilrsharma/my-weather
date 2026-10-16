import XCTest
@testable import MyWeatherCore
#if !SWIFT_PACKAGE && canImport(UIKit)
import SwiftUI
import UIKit
#endif

final class ForecastTests: XCTestCase {
    func testFiveDaysIncludeTodayAndExcludePadding() throws {
        let snapshot = try build()
        let days = try XCTUnwrap(snapshot.forecastDays)
        XCTAssertEqual(days.count, 5)
        XCTAssertEqual(days.map(\.weather.minimumTemperature), [5, 6, 7, 8, 9])
        XCTAssertEqual(snapshot.today, days[0].weather)
        XCTAssertEqual(snapshot.dayTimeline, days[0].timeline)
        XCTAssertEqual(days.map { $0.timeline?.dateLabel }, ["16 Oct", "17 Oct", "18 Oct", "19 Oct", "20 Oct"])
    }

    func testForecastUsesEveryDaysOwnSolarEventsAndHourlyWeather() throws {
        for zone in ["America/Toronto", "Asia/Kolkata"] {
            let fixture = fixture(zone: zone)
            let value = try ForecastBuilder.build(from: JSONSerialization.data(withJSONObject: fixture), timezone: zone)
            let solar = (fixture["daily"] as! [String: Any])["sunrise"] as! [Double]
            let sets = (fixture["daily"] as! [String: Any])["sunset"] as! [Double]
            for (index, day) in try XCTUnwrap(value.forecastDays).enumerated() {
                let timeline = try XCTUnwrap(day.timeline)
                let boundaries = timeline.detailedBlocks.map(\.start) + timeline.detailedBlocks.map(\.end)
                XCTAssertTrue(boundaries.contains(Date(timeIntervalSince1970: solar[index + 1])))
                XCTAssertTrue(boundaries.contains(Date(timeIntervalSince1970: sets[index + 1])))
                XCTAssertGreaterThan(timeline.detailedBlocks.count, 6)
                XCTAssertLessThanOrEqual(timeline.blocks.count, 6)
                XCTAssertTrue(timeline.detailedBlocks.allSatisfy { $0.categories.count == 1 })
                XCTAssertTrue(timeline.detailedBlocks.contains { $0.categories == [.rain] })
                XCTAssertFalse(timeline.detailedBlocks.contains { $0.categories.contains(.dawn) || $0.categories.contains(.lowLight) })
            }
        }
    }

    func testGradientsKeepRealProportionsAndSmoothBoundaries() throws {
        let days = try XCTUnwrap(build().forecastDays)
        for day in days {
            let timeline = try XCTUnwrap(day.timeline)
            let stops = timeline.gradientStops
            XCTAssertEqual(stops.first?.location, 0)
            XCTAssertEqual(stops.last?.location, 1)
            XCTAssertTrue(stops.allSatisfy { (0...1).contains($0.location) })
            XCTAssertTrue(zip(stops, stops.dropFirst()).allSatisfy { $0.location <= $1.location })
            XCTAssertTrue(stops.contains { $0.color == 0xDFA52F })
            XCTAssertTrue(stops.contains { $0.color == 0x315C82 })
            let sunrise = try XCTUnwrap(timeline.detailedBlocks.first { $0.categories == [.sunny] }?.start)
            let position = try XCTUnwrap(timeline.position(at: sunrise))
            XCTAssertNotEqual(position, 0.25, accuracy: 0.001)
            XCTAssertTrue(stops.contains { $0.location < position && $0.location > position - 0.03 })
            XCTAssertTrue(stops.contains { $0.location > position && $0.location < position + 0.03 })
        }
        XCTAssertNotEqual(days[0].timeline?.gradientStops, days[4].timeline?.gradientStops)
    }

    func testDSTAndHalfHourChangesCoverEachRealLocalDay() throws {
        for (zone, day) in [("America/Toronto", "2026-10-30"), ("America/Toronto", "2026-03-06"),
                            ("Australia/Lord_Howe", "2026-10-02"), ("Asia/Kathmandu", "2026-10-16")] {
            let value = try build(day: day, zone: zone)
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: zone)!
            let days = try XCTUnwrap(value.forecastDays)
            XCTAssertEqual(days.count, 5)
            for item in days {
                let timeline = try XCTUnwrap(item.timeline)
                let next = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: item.date))
                XCTAssertEqual(timeline.detailedBlocks.first?.start, item.date)
                XCTAssertEqual(timeline.detailedBlocks.last?.end, next)
                XCTAssertNil(timeline.position(at: next))
                XCTAssertEqual(timeline.position(at: item.date), 0)
                XCTAssertTrue(zip(timeline.detailedBlocks, timeline.detailedBlocks.dropFirst()).allSatisfy { $0.end == $1.start })
                XCTAssertTrue(item.isToday(at: next.addingTimeInterval(-1), timezone: zone))
                XCTAssertFalse(item.isToday(at: next, timezone: zone))
            }
        }
    }

    func testLegacyCacheAndNewFiveDayCacheRoundTrip() throws {
        let value = try build()
        var old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as! [String: Any]
        old.removeValue(forKey: "forecastDays")
        var timeline = old["dayTimeline"] as! [String: Any]
        timeline.removeValue(forKey: "periods")
        old["dayTimeline"] = timeline
        let decoded = try JSONDecoder().decode(WeatherSnapshot.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertEqual(decoded.current, value.current)
        XCTAssertEqual(decoded.today, value.today)
        XCTAssertNil(decoded.forecastDays)
        XCTAssertEqual(decoded.dayTimeline?.detailedBlocks, decoded.dayTimeline?.blocks)
        XCTAssertEqual(try JSONDecoder().decode(WeatherSnapshot.self, from: JSONEncoder().encode(value)), value)
    }

    func testMalformedFutureTemperatureAndDuplicateDatesAreRejected() throws {
        for corruptDates in [true, false] {
            var source = fixture()
            var daily = source["daily"] as! [String: Any]
            if corruptDates {
                var dates = daily["time"] as! [Double]
                dates[4] = dates[3]
                daily["time"] = dates
            } else {
                var minimums = daily["temperature_2m_min"] as! [Int]
                minimums[4] = 100
                daily["temperature_2m_min"] = minimums
            }
            source["daily"] = daily
            XCTAssertThrowsError(try ForecastBuilder.build(from: JSONSerialization.data(withJSONObject: source)))
        }
    }

    func testMissingHourlyForecastPreservesDailyTemperatures() throws {
        var source = fixture()
        source["hourly"] = ["invalid": true]
        let value = try ForecastBuilder.build(from: JSONSerialization.data(withJSONObject: source))
        XCTAssertEqual(value.forecastDays?.count, 5)
        XCTAssertTrue(value.forecastDays?.allSatisfy { $0.timeline == nil } == true)
    }

    #if !SWIFT_PACKAGE
    @MainActor
    func testForecastKeepsManualRefreshAndRetainsSavedWeatherOnFailure() async throws {
        let suite = "ForecastCacheTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = CityRepository(defaults: defaults)
        let city = SavedCity(id: 1, name: "Montreal", region: "", country: "Canada",
                             latitude: 45, longitude: -73, timezone: "America/Toronto")
        let value = try build()
        let legacy = WeatherSnapshot(current: value.current, today: value.today, dayTimeline: value.dayTimeline)
        let original = StoredWeatherState(snapshots: [city.id: legacy], lastUpdated: Date(timeIntervalSince1970: 1_700_000_000))
        try repository.save([city])
        try repository.saveWeatherState(original)
        let service = ForecastStubService(value: value)
        let store = WeatherStore(service: service, repository: repository)
        let before = await service.fetchCount
        XCTAssertEqual(before, 0)
        XCTAssertEqual(store.snapshots[city.id], legacy)
        XCTAssertEqual(repository.loadWeatherState(), original)
        await store.refreshAll()
        let after = await service.fetchCount
        XCTAssertEqual(after, 1)
        XCTAssertEqual(store.snapshots[city.id]?.forecastDays?.count, 5)
        let refreshed = repository.loadWeatherState()
        XCTAssertEqual(refreshed.snapshots[city.id], value)
        let offlineStore = WeatherStore(service: ForecastStubService(value: value, fails: true), repository: repository)
        await offlineStore.refreshAll()
        XCTAssertEqual(offlineStore.snapshots, refreshed.snapshots)
        XCTAssertEqual(offlineStore.lastUpdated, refreshed.lastUpdated)
        XCTAssertEqual(repository.loadWeatherState(), refreshed)
        XCTAssertEqual(repository.load(), [city])
    }
    #endif

    #if !SWIFT_PACKAGE && canImport(UIKit)
    @MainActor
    func testForecastRowsAndApprovedSwitchRenderAtAllSizes() throws {
        let value = try build()
        let city = SavedCity(id: 1, name: "Saint-Jean-sur-Richelieu", region: "Quebec", country: "Canada",
                             latitude: 45, longitude: -73, timezone: "America/Toronto")
        let now = try XCTUnwrap(value.forecastDays?.first?.date).addingTimeInterval(40_000)
        XCTAssertNotNil(UIImage(named: "TodayIcon"))
        for (name, width, type, size) in [
            ("small", 280.0, DynamicTypeSize.large, 13.0),
            ("phone", 362.0, .large, 13.0),
            ("tablet", 664.0, .large, 13.0),
            ("large-text", 280.0, .accessibility5, 40.0)
        ] {
            let temperatureWidth = max(30, WeatherBarMetrics.naturalTextWidth(["-20°", "40°"], fontSize: size))
            let content = VStack(alignment: .leading, spacing: 8) {
                WeatherViewSwitch(screen: .today) { _ in }
                Text(city.name).font(.weatherHeadline)
                ForecastCityView(city: city, snapshot: value, now: now,
                                 temperatureWidth: temperatureWidth, rowWidth: width)
            }
            .frame(width: width).padding(20).background(Color.black)
            .environment(\.dynamicTypeSize, type).environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.uiImage)
            XCTAssertEqual(image.size.width, width + 40, accuracy: 1)
            let attachment = XCTAttachment(image: image)
            attachment.name = "forecast-\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    @MainActor
    func testForecastFullScreensPreserveOrderAndDoNotFetchOnOpening() async throws {
        let suite = "ForecastScreenTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = CityRepository(defaults: defaults)
        let value = try build()
        let cities = [
            SavedCity(id: 1, name: "Montreal", region: "", country: "Canada", latitude: 45, longitude: -73, timezone: "America/Toronto"),
            SavedCity(id: 2, name: "Mumbai", region: "", country: "India", latitude: 19, longitude: 73, timezone: "Asia/Kolkata")
        ]
        try repository.save(cities)
        let stored = StoredWeatherState(snapshots: [1: value, 2: try build(zone: "Asia/Kolkata")], lastUpdated: Date())
        try repository.saveWeatherState(stored)
        let service = ForecastStubService(value: value)
        let store = WeatherStore(service: service, repository: repository)
        let controller = UIHostingController(rootView: AnyView(EmptyView()))
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        for (name, width, height, type, screen) in [
            ("today-phone", 402.0, 874.0, DynamicTypeSize.large, WeatherScreen.today),
            ("forecast-phone", 402.0, 874.0, .large, .forecast),
            ("forecast-small", 320.0, 568.0, .large, .forecast),
            ("forecast-landscape", 874.0, 402.0, .large, .forecast),
            ("forecast-tablet", 744.0, 1_024.0, .large, .forecast),
            ("forecast-large-text", 402.0, 874.0, .accessibility5, .forecast)
        ] {
            controller.rootView = AnyView(ContentView(initialScreen: screen).id(name)
                .environmentObject(store).environment(\.dynamicTypeSize, type)
                .environment(\.colorScheme, .dark).frame(width: width, height: height))
            controller.view.frame = CGRect(x: 0, y: 0, width: width, height: height)
            try await Task.sleep(for: .milliseconds(200))
            controller.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(size: controller.view.bounds.size).image { _ in
                controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "full-\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        let count = await service.fetchCount
        XCTAssertEqual(count, 0)
        XCTAssertEqual(store.cities, cities)
        XCTAssertEqual(repository.load(), cities)
        XCTAssertEqual(repository.loadWeatherState(), stored)
    }

    @MainActor
    func testMissingHourlyLayoutKeepsCurrentTemperatureAtLargeTextSize() throws {
        var source = fixture()
        source.removeValue(forKey: "hourly")
        let value = try ForecastBuilder.build(from: JSONSerialization.data(withJSONObject: source))
        let day = try XCTUnwrap(value.forecastDays?.first)
        let content = ForecastDayRow(day: day, timezone: "America/Toronto", now: day.date,
                                    currentTemperature: value.current.temperature,
                                    temperatureWidth: 100, stacksTemperatures: true)
            .frame(width: 280).padding(20).background(Color.black)
            .environment(\.dynamicTypeSize, .accessibility5).environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.uiImage)
        XCTAssertEqual(image.size.width, 320, accuracy: 1)
        let attachment = XCTAttachment(image: image)
        attachment.name = "forecast-missing-hourly-large-text"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    #endif

    private func build(day: String = "2026-10-16", zone: String = "America/Toronto") throws -> WeatherSnapshot {
        try ForecastBuilder.build(from: JSONSerialization.data(withJSONObject: fixture(day: day, zone: zone)), timezone: zone)
    }

    private func fixture(day: String = "2026-10-16", zone: String = "America/Toronto") -> [String: Any] {
        let timezone = TimeZone(identifier: zone)!
        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        local.timeZone = timezone
        local.dateFormat = "yyyy-MM-dd HH:mm"
        let now = local.date(from: day + " 12:00")!
        let offset = timezone.secondsFromGMT(for: now)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        let midnight = calendar.startOfDay(for: now)
        let fixed = local.copy() as! DateFormatter
        fixed.timeZone = TimeZone(secondsFromGMT: offset)
        let apiMidnight = fixed.date(from: day + " 00:00")!
        let dates = (-1...5).map { calendar.date(byAdding: .day, value: $0, to: midnight)! }
        let rises = dates.enumerated().map { index, date in
            calendar.date(bySettingHour: zone == "Asia/Kolkata" ? 6 : 7, minute: 11 + index * 3, second: 0, of: date)!
        }
        let sets = dates.enumerated().map { index, date in
            calendar.date(bySettingHour: 18, minute: 23 - index * 2, second: 0, of: date)!
        }
        let hours = (0..<168).map { apiMidnight.addingTimeInterval(Double($0 - 24) * 3_600) }
        let codes = hours.map { date -> Int in
            let hour = calendar.component(.hour, from: date)
            if hour == 14 { return 61 }
            return hour >= 8 && hour < 17 && hour.isMultiple(of: 2) ? 3 : 0
        }
        return [
            "timezone": zone, "utc_offset_seconds": offset,
            "current": ["time": now.timeIntervalSince1970, "temperature_2m": 14, "relative_humidity_2m": 60, "weather_code": 0],
            "daily": [
                "time": (-1...5).map { apiMidnight.addingTimeInterval(Double($0) * 86_400).timeIntervalSince1970 },
                "temperature_2m_min": Array(4...10), "temperature_2m_max": Array(14...20),
                "weather_code": [0, 0, 3, 61, 45, 95, 71], "precipitation_probability_max": Array(repeating: 30, count: 7),
                "sunrise": rises.map(\.timeIntervalSince1970), "sunset": sets.map(\.timeIntervalSince1970)
            ],
            "hourly": ["time": hours.map(\.timeIntervalSince1970), "weather_code": codes,
                       "is_day": hours.map { (7..<19).contains(calendar.component(.hour, from: $0)) ? 1 : 0 }]
        ]
    }
}

#if !SWIFT_PACKAGE
private actor ForecastStubService: WeatherServing {
    let value: WeatherSnapshot
    let fails: Bool
    private(set) var fetchCount = 0

    init(value: WeatherSnapshot, fails: Bool = false) {
        self.value = value
        self.fails = fails
    }

    func searchCities(query: String) async throws -> [SavedCity] { [] }
    func fetchToday(for city: SavedCity) async throws -> WeatherSnapshot {
        fetchCount += 1
        if fails { throw WeatherServiceError.unsuccessfulResponse }
        return value
    }
}
#endif
