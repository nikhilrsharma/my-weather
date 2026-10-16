import XCTest
@testable import MyWeatherCore
#if !SWIFT_PACKAGE && canImport(UIKit)
import SwiftUI
import UIKit
#endif

final class DayTimelineTests: XCTestCase {
    func testClearDayUsesActualSuppliedSolarTimes() throws {
        let timeline = try XCTUnwrap(snapshot(fixture()).dayTimeline)
        XCTAssertEqual(timeline.blocks.map(\.label), ["Night", "Sunny", "Night"])
        XCTAssertEqual(timeline.blocks.map(\.timeLabel), ["00:00–06:45", "06:45–18:15", "18:15–24:00"])
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
        XCTAssertEqual(timeline.blocks.first?.timeLabel, "00:00–06:45")
        XCTAssertEqual(timeline.blocks.last?.timeLabel, "18:15–24:00")
        assertCoverage(timeline, hours: 24)
    }

    func testSpringAndFallDSTCoverActualLocalDay() throws {
        for (date, hours) in [("2026-03-08", 23.0), ("2026-11-01", 25.0)] {
            let timeline = try XCTUnwrap(snapshot(fixture(day: date)).dayTimeline)
            XCTAssertTrue(timeline.blocks.first!.timeLabel.hasPrefix("00"))
            XCTAssertTrue(timeline.blocks.last!.timeLabel.hasSuffix("24:00"))
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
    func testSummaryKeepsCurrentTemperatureSeparateFromDailyCondition() throws {
        let base = try snapshot(fixture())
        let value = WeatherSnapshot(current: base.current, today: TodayForecast(
            minimumTemperature: 8, maximumTemperature: 18, condition: .rain,
            precipitation: base.today.precipitation))
        let summary = WeatherSummaryText(value)
        XCTAssertEqual(summary.current, "14°C")
        XCTAssertEqual(summary.lowHigh, "Low 8°C · High 18°C")
        XCTAssertEqual(summary.humidity, "Humidity 70%")
        XCTAssertEqual(summary.condition, "Rain")
        XCTAssertNotEqual(value.current.condition.rawValue, summary.condition)
        XCTAssertEqual(summary.precipitation, base.today.precipitation.label)
    }

    func testWeatherColumnMeasurementIncludesBadgeAndLocalClock() throws {
        let summary = WeatherSummaryText(try snapshot(fixture()))
        for size in [13.0, 26, 40] {
            let clock = "23:59 GMT+05:45"
            let measured = summary.preferredWidth(clock: clock, fontSize: size)
            let badgeWidth = WeatherBarMetrics.naturalTextWidth([summary.humidity + " ·"], fontSize: size)
                + DailyConditionRow.spacing
                + WeatherBarMetrics.naturalTextWidth([summary.condition], fontSize: size)
                + 2 * DailyConditionBadge.horizontalInset
            XCTAssertGreaterThanOrEqual(measured, badgeWidth)
            XCTAssertGreaterThanOrEqual(measured, WeatherBarMetrics.naturalTextWidth([clock], fontSize: size))
        }
        XCTAssertGreaterThan(summary.preferredWidth(clock: "Time Unavailable", fontSize: 26),
                             summary.preferredWidth(clock: "Time Unavailable", fontSize: 13) * 1.8)
    }

    func testEveryDailyConditionBadgeHasReadableDarkModeContrast() {
        func luminance(_ hex: UInt32) -> Double {
            let channels = [16, 8, 0].map { shift -> Double in
                let channel = Double((hex >> shift) & 0xFF) / 255
                return channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
            }
            return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722
        }
        func contrast(_ first: UInt32, _ second: UInt32) -> Double {
            let a = luminance(first), b = luminance(second)
            return (max(a, b) + 0.05) / (min(a, b) + 0.05)
        }
        for condition in WholeDayCondition.allCases {
            let palette = DailyConditionPalette(condition)
            XCTAssertGreaterThanOrEqual(contrast(palette.foregroundHex, palette.backgroundHex), 4.5, condition.rawValue)
            XCTAssertGreaterThanOrEqual(contrast(palette.borderHex, palette.backgroundHex), 3, condition.rawValue)
            XCTAssertGreaterThanOrEqual(contrast(palette.borderHex, 0x2C2C2E), 3, condition.rawValue)
        }
    }

    func testDailyConditionPaletteGroupsRelatedWeatherWithoutLosingLabels() {
        XCTAssertEqual(DailyConditionPalette(.rain), DailyConditionPalette(.showers))
        XCTAssertEqual(DailyConditionPalette(.snow), DailyConditionPalette(.snowShowers))
        XCTAssertEqual(DailyConditionPalette(.freezingRain), DailyConditionPalette(.freezingDrizzle))
        XCTAssertNotEqual(DailyConditionPalette(.sunny), DailyConditionPalette(.rain))
        XCTAssertNotEqual(DailyConditionPalette(.fog), DailyConditionPalette(.cloudy))
        XCTAssertNotEqual(DailyConditionPalette(.unknown), DailyConditionPalette(.sunny))
    }

    func testResponsiveColumnsUseEveryAvailablePoint() {
        for width in [240.0, 280, 335, 362, 390, 664, 704, 984, 1_400] {
            let sizing = CityWeatherSizing(rowWidth: width, preferredTextWidth: 250,
                                           minimumTimelineWidth: 210, forceStacked: false)
            if sizing.isStacked {
                XCTAssertEqual(sizing.timelineWidth, width)
                XCTAssertEqual(sizing.textWidth, width)
            } else {
                XCTAssertEqual(sizing.textWidth + CityWeatherSizing.spacing + sizing.timelineWidth, width)
                XCTAssertGreaterThanOrEqual(sizing.timelineWidth, 210)
                XCTAssertEqual(sizing.textWidth, 250)
            }
        }
    }

    func testWiderWindowsExpandBarsInsteadOfLeavingUnusedSpace() {
        let sizing = CityWeatherSizing(rowWidth: 600, preferredTextWidth: 250,
                                       minimumTimelineWidth: 210, forceStacked: false)
        XCTAssertEqual(sizing.fitting(1_000).timelineWidth - sizing.timelineWidth, 400)
        XCTAssertTrue(sizing.fitting(320).isStacked)
        XCTAssertEqual(sizing.fitting(320).timelineWidth, 320)
        XCTAssertEqual(sizing.fitting(320).fitting(600).timelineWidth, sizing.timelineWidth)
    }

    func testAccessibilityTextAlwaysGetsFullWidthAndSharedBarHeight() throws {
        let blocks = try XCTUnwrap(snapshot(fixture()).dayTimeline).blocks
        for width in [240.0, 320, 704, 984] {
            let sizing = CityWeatherSizing(rowWidth: width, preferredTextWidth: 600,
                                           minimumTimelineWidth: 600, forceStacked: true)
            XCTAssertTrue(sizing.isStacked)
            XCTAssertEqual(sizing.timelineWidth, width)
            let metrics = WeatherBarMetrics(blocks: blocks, width: sizing.timelineWidth, fontSize: 34)
            XCTAssertEqual(metrics.width, width)
            XCTAssertGreaterThan(metrics.height, 0)
            if metrics.stacksText {
                XCTAssertEqual(metrics.labelWidth + 34, width, accuracy: 0.01)
            } else {
                XCTAssertEqual(metrics.timeWidth + metrics.labelWidth + 41, width, accuracy: 0.01)
            }
        }
    }

    func testWeatherTextMeasurementKeepsCompleteLinesTogether() {
        let strings = ["Low -20°C · High 12°C", "Humidity 100% · Mix of Sun and Clouds", "Chance of Precipitation 100%"]
        let normal = WeatherBarMetrics.naturalTextWidth(strings, fontSize: 13)
        let larger = WeatherBarMetrics.naturalTextWidth(strings, fontSize: 26)
        XCTAssertGreaterThan(normal, 200)
        XCTAssertGreaterThan(larger, normal * 1.9)
        XCTAssertEqual(WeatherBarMetrics.naturalTextWidth([], fontSize: 13), 0)
    }

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
            let textWidth = metrics.stacksText ? metrics.labelWidth : metrics.timeWidth + metrics.gap + metrics.labelWidth
            XCTAssertEqual(textWidth + metrics.leadingInset + metrics.trailingInset
                + metrics.dotDiameter + metrics.gap, width, accuracy: 0.01)
            XCTAssertGreaterThan(metrics.labelWidth, 0)
            XCTAssertEqual(metrics.trailingInset, 10)
            XCTAssertEqual(metrics.dotDiameter, 9)
            let shortOnly = WeatherBarMetrics(blocks: timeline.blocks, width: width, fontSize: size)
            XCTAssertGreaterThanOrEqual(metrics.height, shortOnly.height)
        }
    }

    func testNarrowBarsStackTextBeforeBreakingWeatherWords() throws {
        let block = DayWeatherBlock(start: Date(), end: Date().addingTimeInterval(3_600),
            timeLabel: "06–07", accessibleTimeLabel: "Six to Seven", categories: [.nightDrizzle, .ice])
        let narrow = WeatherBarMetrics(blocks: [block], width: 280, fontSize: 34)
        XCTAssertTrue(narrow.stacksText)
        XCTAssertEqual(narrow.timeWidth, narrow.labelWidth)
        XCTAssertGreaterThan(narrow.labelWidth, WeatherBarMetrics.naturalTextWidth(["Freezing", "Drizzle"], fontSize: 34))
        let wide = WeatherBarMetrics(blocks: [block], width: 700, fontSize: 11)
        XCTAssertFalse(wide.stacksText)
    }
    #endif

    #if !SWIFT_PACKAGE && canImport(UIKit)
    @MainActor
    func testResponsiveCityRowRenderMatrix() throws {
        let base = try snapshot(fixture())
        let timeline = try XCTUnwrap(base.dayTimeline)
        let extra = DayWeatherBlock(start: timeline.blocks[1].start, end: timeline.blocks[1].end,
                                   timeLabel: "06–07", accessibleTimeLabel: "Six to Seven",
                                   categories: [.nightDrizzle, .ice])
        var blocks = timeline.blocks
        blocks[1] = extra
        let value = WeatherSnapshot(current: base.current, today: base.today,
            dayTimeline: DayTimeline(dateLabel: timeline.dateLabel, timezone: timeline.timezone, blocks: blocks))
        let city = SavedCity(id: 1, name: "Saint-Jean-sur-Richelieu", region: "Quebec", country: "Canada",
                             latitude: 45.3, longitude: -73.3, timezone: "America/Toronto")
        for (name, width, type, category) in [
            ("small-phone", 280.0, DynamicTypeSize.large, UIContentSizeCategory.large),
            ("phone", 362.0, .large, .large),
            ("phone-landscape", 704.0, .large, .large),
            ("tablet-portrait", 664.0, .large, .large),
            ("tablet-landscape", 984.0, .large, .large),
            ("small-accessibility", 280.0, .accessibility5, .accessibilityExtraExtraExtraLarge),
            ("phone-accessibility", 362.0, .accessibility5, .accessibilityExtraExtraExtraLarge),
            ("tablet-accessibility", 704.0, .accessibility5, .accessibilityExtraExtraExtraLarge)
        ] {
            let traits = UITraitCollection(preferredContentSizeCategory: category)
            let fontSize = UIFontMetrics(forTextStyle: .footnote).scaledValue(for: 11, compatibleWith: traits)
            let textSize = UIFontMetrics(forTextStyle: .subheadline).scaledValue(for: 13, compatibleWith: traits)
            let sizing = CityWeatherSizing(rowWidth: width,
                preferredTextWidth: WeatherSummaryText(value).preferredWidth(
                    clock: CityClock.text(at: extra.start, timezone: city.timezone), fontSize: textSize),
                minimumTimelineWidth: 210 * fontSize / 11, forceStacked: type.isAccessibilitySize)
            let metrics = WeatherBarMetrics(blocks: blocks, width: sizing.timelineWidth, fontSize: fontSize)
            let view = CityRow(city: city, snapshot: value, isUnavailable: false,
                              now: extra.start, sizing: sizing, metrics: metrics)
                .frame(width: width).padding(20).background(Color.black)
                .environment(\.colorScheme, .dark).environment(\.dynamicTypeSize, type)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.uiImage)
            XCTAssertEqual(image.size.width, width + 40, accuracy: 1)
            let attachment = XCTAttachment(image: image)
            attachment.name = "responsive-row-\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    @MainActor
    func testDailyConditionBadgeRenderMatrixAndMissingWeather() throws {
        for (name, width, type) in [
            ("compact", 280.0, DynamicTypeSize.large),
            ("wide", 664.0, .large),
            ("largest-text", 280.0, .accessibility5)
        ] {
            let view = VStack(alignment: .leading, spacing: 12) {
                ForEach(WholeDayCondition.allCases, id: \.self) { condition in
                    DailyConditionRow(humidity: "Humidity 100%", condition: condition)
                }
            }
            .frame(width: width, alignment: .leading).padding(20)
            .background(Color(white: 0.11))
            .environment(\.colorScheme, .dark).environment(\.dynamicTypeSize, type)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.uiImage)
            XCTAssertEqual(image.size.width, width + 40, accuracy: 1)
            let attachment = XCTAttachment(image: image)
            attachment.name = "daily-badges-\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        let city = SavedCity(id: 100, name: "Mumbai", region: "", country: "India",
                             latitude: 19, longitude: 73, timezone: "Asia/Kolkata")
        let value = try snapshot(fixture())
        let legacy = WeatherSnapshot(current: value.current, today: value.today)
        let sizing = CityWeatherSizing(rowWidth: 280, preferredTextWidth: 250,
                                       minimumTimelineWidth: 210, forceStacked: false)
        let metrics = WeatherBarMetrics(blocks: [], width: 280, fontSize: 11)
        let rows = VStack(alignment: .leading, spacing: 20) {
            CityRow(city: city, snapshot: nil, isUnavailable: true, now: Date(), sizing: sizing, metrics: metrics)
            CityRow(city: city, snapshot: legacy, isUnavailable: false, now: Date(), sizing: sizing, metrics: metrics)
        }
        .frame(width: 280).padding(20).background(Color.black).environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: rows)
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.uiImage)
        XCTAssertEqual(image.size.width, 320, accuracy: 1)
        let attachment = XCTAttachment(image: image)
        attachment.name = "daily-badges-missing-and-legacy-weather"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testResponsiveMainSearchAndAboutScreens() async throws {
        let suite = "MyWeatherResponsiveTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = CityRepository(defaults: defaults)
        let value = try snapshot(fixture())
        let cities = ["Montreal", "Saint-Jean-sur-Richelieu", "Mumbai"].enumerated().map { index, name in
            SavedCity(id: index, name: name, region: "", country: "", latitude: 0, longitude: 0,
                      timezone: index == 2 ? "Asia/Kolkata" : "America/Toronto")
        }
        try repository.save(cities)
        try repository.saveWeatherState(StoredWeatherState(
            snapshots: Dictionary(uniqueKeysWithValues: cities.map { ($0.id, value) }), lastUpdated: Date()))
        let store = WeatherStore(repository: repository)
        let controller = UIHostingController(rootView: AnyView(EmptyView()))
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        // Reuse the same host while changing size, exercising rotation/window resize.
        for (name, width, height, type) in [
            ("small-phone", 320.0, 568.0, DynamicTypeSize.large),
            ("phone", 402.0, 874.0, .large),
            ("landscape", 874.0, 402.0, .large),
            ("tablet", 744.0, 1_024.0, .large),
            ("wide-tablet", 1_024.0, 744.0, .large),
            ("phone-again", 402.0, 874.0, .large),
            ("largest-text", 402.0, 874.0, .accessibility5)
        ] {
            controller.rootView = AnyView(ContentView().environmentObject(store)
                .environment(\.dynamicTypeSize, type).environment(\.colorScheme, .dark)
                .frame(width: width, height: height))
            controller.view.frame = CGRect(x: 0, y: 0, width: width, height: height)
            try await Task.sleep(for: .milliseconds(200))
            controller.view.layoutIfNeeded()
            attachScreen(controller.view, name: "responsive-main-\(name)")
        }
        for (name, screen) in [
            ("about", AnyView(AboutView(lastUpdated: Date()))),
            ("search", AnyView(AddCityView().environmentObject(store)))
        ] {
            controller.rootView = AnyView(screen.environment(\.dynamicTypeSize, .accessibility5)
                .environment(\.colorScheme, .dark).frame(width: 402, height: 874))
            controller.view.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
            try await Task.sleep(for: .milliseconds(200))
            controller.view.layoutIfNeeded()
            attachScreen(controller.view, name: "responsive-\(name)-largest-text")
        }
        XCTAssertEqual(repository.load(), cities)
        XCTAssertEqual(repository.loadWeatherState().snapshots.count, 3)
    }

    @MainActor
    private func attachScreen(_ view: UIView, name: String) {
        let image = UIGraphicsImageRenderer(size: view.bounds.size).image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
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
