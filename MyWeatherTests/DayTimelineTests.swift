import XCTest
@testable import MyWeatherCore

final class DayTimelineTests: XCTestCase {
    func testClearDayMatchesSixReadableLightPeriods() throws {
        let timeline = try XCTUnwrap(snapshot(fixture()).dayTimeline)
        XCTAssertEqual(timeline.blocks.map(\.label), ["Night", "Dawn", "Sunny", "Low Light", "Dusk", "Night"])
        XCTAssertEqual(timeline.blocks.map(\.timeLabel), ["00–06", "06–07", "07–17", "17–18", "18–19", "19–24"])
        XCTAssertEqual(timeline.dateLabel, "13 Oct")
        XCTAssertEqual(timeline.timezone, "America/Toronto")
        assertCoverage(timeline, hours: 24)
    }

    func testTodayNotYesterdaySelectedFromPaddedResponse() throws {
        let value = try snapshot(fixture())
        XCTAssertEqual(value.today.minimumTemperature, 8)
        XCTAssertEqual(value.today.maximumTemperature, 18)
        XCTAssertEqual(value.today.precipitation.probability, 20)
        XCTAssertEqual(value.current.temperature, 14)
    }

    func testLateRefreshStillShowsEntireDay() throws {
        let data = fixture(hour: 23)
        let timeline = try XCTUnwrap(snapshot(data).dayTimeline)
        XCTAssertEqual(timeline.blocks.first?.timeLabel, "00–06")
        XCTAssertEqual(timeline.blocks.last?.timeLabel, "19–24")
        assertCoverage(timeline, hours: 24)
    }

    func testSpringAndFallDSTCoverActualLocalDay() throws {
        for (date, hours) in [("2026-03-08", 23.0), ("2026-11-01", 25.0)] {
            let timeline = try XCTUnwrap(snapshot(fixture(day: date)).dayTimeline)
            XCTAssertTrue(timeline.blocks.first!.timeLabel.hasPrefix("00–"))
            XCTAssertTrue(timeline.blocks.last!.timeLabel.hasSuffix("–24"))
            assertCoverage(timeline, hours: hours)
        }
    }

    func testHalfHourDSTAndNonWholeHourTimezones() throws {
        for (zone, date, hours) in [
            ("Australia/Lord_Howe", "2026-10-04", 23.5),
            ("Australia/Lord_Howe", "2026-04-05", 24.5),
            ("Asia/Kolkata", "2026-10-13", 24.0),
            ("Asia/Kathmandu", "2026-10-13", 24.0)
        ] {
            let timeline = try XCTUnwrap(snapshot(fixture(day: date, zone: zone)).dayTimeline)
            assertCoverage(timeline, hours: hours)
            XCTAssertEqual(timeline.timezone, zone)
        }
    }

    func testCityTimezoneOverridesResponseAliasAndDeviceTimezone() throws {
        var data = fixture(zone: "Asia/Kolkata", hour: 0)
        data["timezone"] = "UTC"
        let value = try ForecastBuilder.build(from: JSONSerialization.data(withJSONObject: data), timezone: "Asia/Kolkata")
        XCTAssertEqual(value.dayTimeline?.dateLabel, "13 Oct")
        XCTAssertEqual(value.dayTimeline?.timezone, "Asia/Kolkata")
        XCTAssertEqual(value.today.minimumTemperature, 8)
    }

    func testWetWeatherIsVisibleDuringDayAndNight() throws {
        for (code, day, night) in [
            (45, DayWeatherCategory.fog, DayWeatherCategory.nightFog),
            (51, .drizzle, .nightDrizzle),
            (61, .rain, .nightRain),
            (66, .ice, .nightIce),
            (71, .snow, .nightSnow),
            (95, .storms, .nightStorms)
        ] {
            let timeline = try XCTUnwrap(snapshot(fixture(weatherCode: { _ in code })).dayTimeline)
            XCTAssertTrue(timeline.blocks.contains { $0.categories.contains(day) })
            XCTAssertTrue(timeline.blocks.contains { $0.categories.contains(night) })
            XCTAssertFalse(timeline.blocks.contains { $0.categories.contains(.sunny) })
            assertCoverage(timeline, hours: 24)
        }
    }

    func testVariableWeatherCombinesToSixWithoutLosingStorms() throws {
        let timeline = try XCTUnwrap(snapshot(fixture(weatherCode: { hour in
            if hour == 12 { return 95 }
            return hour.isMultiple(of: 2) ? 0 : 3
        })).dayTimeline)
        XCTAssertLessThanOrEqual(timeline.blocks.count, 6)
        XCTAssertTrue(timeline.blocks.contains { $0.label.contains("Storms") })
        XCTAssertTrue(timeline.blocks.contains { $0.label == "Sun / Cloud" })
        assertCoverage(timeline, hours: 24)
    }

    func testMissingHourlyValueIsNotDisplayedAsSunny() throws {
        var data = fixture()
        var hourly = data["hourly"] as! [String: Any]
        var codes = hourly["weather_code"] as! [Any]
        codes[36] = NSNull()
        hourly["weather_code"] = codes
        data["hourly"] = hourly
        let timeline = try XCTUnwrap(snapshot(data).dayTimeline)
        XCTAssertTrue(timeline.blocks.contains { $0.categories.contains(.unknown) })
        assertCoverage(timeline, hours: 24)
    }

    func testInvalidHourlyChartNeverHidesValidCurrentWeather() throws {
        for invalidHourly: Any in [NSNull(), "bad response", ["time": []], [
            "time": [0, 3_600], "weather_code": [0], "is_day": [1, 1]
        ]] {
            var data = fixture()
            data["hourly"] = invalidHourly
            let value = try snapshot(data)
            XCTAssertNil(value.dayTimeline)
            XCTAssertEqual(value.current.temperature, 14)
            XCTAssertEqual(value.today.minimumTemperature, 8)
        }
    }

    func testIncompleteDayOrGapsAreNotInvented() throws {
        for cut in [true, false] {
            var data = fixture()
            var hourly = data["hourly"] as! [String: Any]
            if cut {
                for key in ["time", "weather_code", "is_day"] {
                    hourly[key] = Array((hourly[key] as! [Any]).suffix(24))
                }
            } else {
                var times = hourly["time"] as! [Double]
                times[36] += 1
                hourly["time"] = times
            }
            data["hourly"] = hourly
            XCTAssertNil(try snapshot(data).dayTimeline)
        }
    }

    func testPolarDayAndNightDoNotInventSunrise() throws {
        for isDay in [0, 1] {
            var data = fixture()
            var daily = data["daily"] as! [String: Any]
            daily["sunrise"] = [NSNull(), NSNull(), NSNull()]
            daily["sunset"] = [0, 0, 0]
            data["daily"] = daily
            var hourly = data["hourly"] as! [String: Any]
            hourly["is_day"] = Array(repeating: isDay, count: 72)
            data["hourly"] = hourly
            let timeline = try XCTUnwrap(snapshot(data).dayTimeline)
            XCTAssertEqual(timeline.blocks.map(\.label), [isDay == 0 ? "Night" : "Sunny"])
            assertCoverage(timeline, hours: 24)
        }
    }

    func testTimelinePersistsAndLegacySnapshotStillDecodes() throws {
        let value = try snapshot(fixture())
        let state = StoredWeatherState(snapshots: [1: value], lastUpdated: Date(timeIntervalSince1970: 1_800_000_000))
        let suiteName = "DayTimelineTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let repository = CityRepository(defaults: defaults)
        try repository.saveWeatherState(state)
        XCTAssertEqual(repository.loadWeatherState(), state)

        let encoded = try JSONEncoder().encode(value)
        var legacy = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        legacy.removeValue(forKey: "dayTimeline")
        let decoded = try JSONDecoder().decode(WeatherSnapshot.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(decoded.dayTimeline)
        XCTAssertEqual(decoded.today, value.today)
        XCTAssertEqual(decoded.current, value.current)
    }

    func testAllWeatherCategoryLabelsUseConsistentTitleCase() {
        XCTAssertEqual(DayWeatherCategory.allCases.map(\.label), [
            "Night", "Dawn", "Sunny", "Sun / Cloud", "Cloudy", "Low Light", "Dusk",
            "Fog", "Drizzle", "Rain", "Freezing Rain", "Snow", "Storms",
            "Night Fog", "Night Drizzle", "Night Rain", "Night Ice", "Night Snow", "Night Storms",
            "Unavailable"
        ])

        let labels = WholeDayCondition.allCases.map(\.rawValue)
            + WeatherCondition.allCases.map(\.rawValue)
            + PrecipitationKind.allCases.map(\.rawValue)
        for label in labels {
            for word in label.split(separator: " ") where word != "of" && word != "and" {
                let firstLetter = String(word.prefix(1))
                XCTAssertEqual(firstLetter, firstLetter.uppercased(), label)
            }
        }
    }

    func testMixedPeriodLabelsUseTheSameTitleCase() {
        func label(_ categories: [DayWeatherCategory]) -> String {
            DayWeatherBlock(
                start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 3_600),
                timeLabel: "00–01", accessibleTimeLabel: "00:00 to 01:00", categories: categories
            ).label
        }
        XCTAssertEqual(label([.sunny, .cloudy]), "Sun / Cloud")
        XCTAssertEqual(label([.dawn, .rain, .cloudy]), "Rain / Mix")
        XCTAssertEqual(label([.night, .nightRain]), "Night Rain / Night")
    }

    func testCachedBlocksUseNewLabelsWithoutChangingStoredCategoryIDs() throws {
        // These are the category IDs saved by version 1.4, not display strings.
        let cases = [
            ("lowLight", "Low Light"), ("partlyCloudy", "Sun / Cloud"),
            ("nightRain", "Night Rain"), ("nightDrizzle", "Night Drizzle")
        ]
        for (id, label) in cases {
            let data = Data("""
            {"start":0,"end":3600,"timeLabel":"00–01","accessibleTimeLabel":"00:00 to 01:00","categories":["\(id)"]}
            """.utf8)
            let cached = try JSONDecoder().decode(DayWeatherBlock.self, from: data)
            XCTAssertEqual(cached.label, label)
            let saved = try JSONSerialization.jsonObject(with: JSONEncoder().encode(cached)) as! [String: Any]
            XCTAssertEqual(saved["categories"] as? [String], [id])
        }
    }

    private func snapshot(_ data: [String: Any]) throws -> WeatherSnapshot {
        try ForecastBuilder.build(from: JSONSerialization.data(withJSONObject: data))
    }

    func testCityClocksShowSameInstantInTheirOwnTimezones() throws {
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-13T17:45:00Z"))
        XCTAssertEqual(CityClock.text(at: date, timezone: "America/Toronto"), "13:45 EDT")
        XCTAssertEqual(CityClock.text(at: date, timezone: "Asia/Kolkata"), "23:15 IST")
        XCTAssertTrue(CityClock.text(at: date, timezone: "Asia/Kathmandu").hasPrefix("23:30 "))
    }

    func testCityClockChangesDateAndHonorsMidnightWithoutUsing24() throws {
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-13T18:30:00Z"))
        XCTAssertEqual(CityClock.text(at: date, timezone: "Asia/Kolkata"), "00:00 IST")
        XCTAssertEqual(CityClock.text(at: date.addingTimeInterval(11_700), timezone: "Asia/Kolkata"), "03:15 IST")
    }

    func testCityClockChangesAbbreviationAcrossDaylightSavingTime() throws {
        let first = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-01T05:30:00Z"))
        XCTAssertEqual(CityClock.text(at: first, timezone: "America/Toronto"), "01:30 EDT")
        XCTAssertEqual(CityClock.text(at: first.addingTimeInterval(3_600), timezone: "America/Toronto"), "01:30 EST")
        let spring = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-03-08T06:59:00Z"))
        XCTAssertEqual(CityClock.text(at: spring, timezone: "America/Toronto"), "01:59 EST")
        XCTAssertEqual(CityClock.text(at: spring.addingTimeInterval(60), timezone: "America/Toronto"), "03:00 EDT")
    }

    func testInvalidCityTimezoneNeverFallsBackToDeviceTime() {
        XCTAssertEqual(CityClock.text(at: Date(), timezone: "invalid/timezone"), "Time Unavailable")
    }

    func testNowDotUsesExactlyOneBlockAndMovesAtItsBoundary() throws {
        let timeline = try XCTUnwrap(snapshot(fixture()).dayTimeline)
        for block in timeline.blocks {
            XCTAssertEqual(timeline.currentBlockID(at: block.start), block.id)
            XCTAssertEqual(timeline.currentBlockID(at: block.end.addingTimeInterval(-0.001)), block.id)
            XCTAssertNotEqual(timeline.currentBlockID(at: block.end), block.id)
        }
        for (left, right) in zip(timeline.blocks, timeline.blocks.dropFirst()) {
            XCTAssertEqual(timeline.currentBlockID(at: left.end), right.id)
        }
    }

    func testNowDotIsHiddenOutsideCachedDayAndForEmptyTimelines() throws {
        let timeline = try XCTUnwrap(snapshot(fixture()).dayTimeline)
        XCTAssertNil(timeline.currentBlockID(at: timeline.blocks.first!.start.addingTimeInterval(-1)))
        XCTAssertNil(timeline.currentBlockID(at: timeline.blocks.last!.end))
        XCTAssertNil(timeline.currentBlockID(at: timeline.blocks.last!.end.addingTimeInterval(86_400)))
        XCTAssertNil(DayTimeline(dateLabel: "", timezone: "UTC", blocks: []).currentBlockID(at: Date()))
    }

    func testNowDotHandlesDSTAndDoesNotMutateCachedWeather() throws {
        for (date, zone) in [("2026-11-01", "America/Toronto"), ("2026-10-04", "Australia/Lord_Howe")] {
            let value = try snapshot(fixture(day: date, zone: zone))
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            let original = try encoder.encode(value)
            let timeline = try XCTUnwrap(value.dayTimeline)
            var now = timeline.blocks.first!.start
            while now < timeline.blocks.last!.end {
                XCTAssertNotNil(timeline.currentBlockID(at: now))
                _ = CityClock.text(at: now, timezone: zone)
                now = now.addingTimeInterval(60)
            }
            XCTAssertEqual(try encoder.encode(value), original)
        }
    }

    #if !SWIFT_PACKAGE
    func testSharedBarMetricsReserveTextAndFixedMarkerSpaceAtAllTextSizes() throws {
        let timeline = try XCTUnwrap(snapshot(fixture()).dayTimeline)
        let longBlock = DayWeatherBlock(
            start: Date(), end: Date().addingTimeInterval(3_600),
            timeLabel: "01:00 EDT–01:00 EST", accessibleTimeLabel: "Repeated Hour",
            categories: [.nightDrizzle, .ice]
        )
        for (width, size) in [(174.0, 11.0), (280.0, 22.0), (280.0, 34.0)] {
            let metrics = WeatherBarMetrics(blocks: timeline.blocks + [longBlock], width: width, fontSize: size)
            XCTAssertEqual(metrics.width, width)
            XCTAssertGreaterThanOrEqual(metrics.height, 28 * size / 11)
            XCTAssertEqual(metrics.timeWidth + metrics.labelWidth + metrics.leadingInset
                + metrics.trailingInset + metrics.dotDiameter + 2 * metrics.gap, width, accuracy: 0.01)
            XCTAssertGreaterThan(metrics.labelWidth, 0)
            XCTAssertEqual(metrics.trailingInset, 10)
            XCTAssertEqual(metrics.dotDiameter, 9)
            let shortOnly = WeatherBarMetrics(blocks: timeline.blocks, width: width, fontSize: size)
            XCTAssertGreaterThanOrEqual(metrics.height, shortOnly.height)
        }
    }
    #endif

    private func assertCoverage(_ timeline: DayTimeline, hours: Double, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertLessThanOrEqual(timeline.blocks.count, 6, file: file, line: line)
        XCTAssertFalse(timeline.blocks.isEmpty, file: file, line: line)
        XCTAssertTrue(timeline.blocks.allSatisfy { $0.start < $0.end }, file: file, line: line)
        XCTAssertTrue(zip(timeline.blocks, timeline.blocks.dropFirst()).allSatisfy { $0.end == $1.start }, file: file, line: line)
        XCTAssertEqual(timeline.blocks.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }, hours * 3_600, accuracy: 0.1, file: file, line: line)
    }

    private func fixture(
        day: String = "2026-10-13", zone: String = "America/Toronto", hour: Int = 12,
        weatherCode: (Int) -> Int = { _ in 0 }
    ) -> [String: Any] {
        let timezone = TimeZone(identifier: zone)!
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timezone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let now = formatter.date(from: "\(day) \(String(format: "%02d", hour)):00")!
        let rise = formatter.date(from: "\(day) 06:45")!
        let set = formatter.date(from: "\(day) 18:15")!
        // Match Open-Meteo's fixed offset boundaries, including on a DST day.
        let offset = timezone.secondsFromGMT(for: now)
        formatter.timeZone = TimeZone(secondsFromGMT: offset)
        let midnight = formatter.date(from: "\(day) 00:00")!
        let start = midnight.addingTimeInterval(-86_400)
        let times = (0..<72).map { start.addingTimeInterval(Double($0) * 3_600) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        let codes = times.map { weatherCode(calendar.component(.hour, from: $0)) }
        let daylight = times.map { date -> Int in
            let hour = calendar.component(.hour, from: date)
            return (7...18).contains(hour) ? 1 : 0
        }
        return [
            "timezone": zone, "utc_offset_seconds": offset,
            "current": ["time": now.timeIntervalSince1970, "temperature_2m": 14, "relative_humidity_2m": 70, "weather_code": 0],
            "daily": [
                "time": [-1, 0, 1].map { midnight.addingTimeInterval(Double($0) * 86_400).timeIntervalSince1970 },
                "temperature_2m_min": [2, 8, 10], "temperature_2m_max": [12, 18, 20],
                "weather_code": [61, 0, 3], "precipitation_probability_max": [90, 20, 50],
                "sunrise": [rise.addingTimeInterval(-86_400), rise, rise.addingTimeInterval(86_400)].map(\.timeIntervalSince1970),
                "sunset": [set.addingTimeInterval(-86_400), set, set.addingTimeInterval(86_400)].map(\.timeIntervalSince1970)
            ],
            "hourly": ["time": times.map(\.timeIntervalSince1970), "weather_code": codes, "is_day": daylight]
        ]
    }
}
