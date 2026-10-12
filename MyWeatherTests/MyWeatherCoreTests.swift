import XCTest
@testable import MyWeatherCore

final class MyWeatherCoreTests: XCTestCase {
    func testConditionMappingCoversOpenMeteoGroups() {
        XCTAssertEqual(WeatherCondition(wmoCode: 0), .clear)
        XCTAssertEqual(WeatherCondition(wmoCode: 2), .cloudy)
        XCTAssertEqual(WeatherCondition(wmoCode: 45), .fog)
        XCTAssertEqual(WeatherCondition(wmoCode: 53), .drizzle)
        XCTAssertEqual(WeatherCondition(wmoCode: 81), .rain)
        XCTAssertEqual(WeatherCondition(wmoCode: 73), .snow)
        XCTAssertEqual(WeatherCondition(wmoCode: 96), .thunderstorm)
        XCTAssertEqual(WeatherCondition(wmoCode: -1), .unknown)
    }

    func testForecastBuildsCurrentAndDailyWeatherWithoutHourlyData() throws {
        let snapshot = try ForecastBuilder.build(from: forecastData())

        XCTAssertEqual(snapshot.current, CurrentWeather(temperature: 13.6, humidity: 72, condition: .cloudy))
        XCTAssertEqual(snapshot.today.minimumTemperature, -2)
        XCTAssertEqual(snapshot.today.maximumTemperature, 19)
        XCTAssertEqual(snapshot.today.condition, .sunCloudMix)
        XCTAssertEqual(snapshot.today.precipitation, PrecipitationChance(kind: .precipitation, probability: 70))
        XCTAssertEqual(snapshot.today.precipitation.label, "Chance of precipitation 70%")
    }

    func testDailyConditionAndPrecipitationLabelsUseDailyWeatherCode() throws {
        let cases: [(Int, WholeDayCondition, PrecipitationKind, String)] = [
            (0, .sunny, .precipitation, "Chance of precipitation 60%"),
            (3, .cloudy, .precipitation, "Chance of precipitation 60%"),
            (53, .drizzle, .drizzle, "Drizzle 60%"),
            (67, .freezingRain, .freezingRain, "Freezing Rain 60%"),
            (61, .rain, .rain, "Rain 60%"),
            (71, .snow, .snow, "Snow 60%"),
            (85, .snowShowers, .snowShowers, "Snow Showers 60%"),
            (95, .thunderstorm, .thunderstorm, "Thunderstorm 60%")
        ]

        for (code, condition, kind, label) in cases {
            let snapshot = try ForecastBuilder.build(
                from: forecastData(
                    dailyWeatherCode: code,
                    dailyPrecipitationProbability: 60
                )
            )

            XCTAssertEqual(snapshot.today.condition, condition)
            XCTAssertEqual(snapshot.today.precipitation.kind, kind)
            XCTAssertEqual(snapshot.today.precipitation.label, label)
        }
    }

    func testMissingDailyPrecipitationProbabilityPreservesOtherDailyValues() throws {
        let snapshot = try ForecastBuilder.build(
            from: forecastData(
                dailyWeatherCode: 61,
                dailyPrecipitationProbability: nil,
                dailyMinimumTemperature: 4,
                dailyMaximumTemperature: 12
            )
        )

        XCTAssertEqual(snapshot.today.minimumTemperature, 4)
        XCTAssertEqual(snapshot.today.maximumTemperature, 12)
        XCTAssertEqual(snapshot.today.condition, .rain)
        XCTAssertEqual(snapshot.today.precipitation, PrecipitationChance(kind: .rain, probability: nil))
        XCTAssertEqual(snapshot.today.precipitation.label, "Rain —")
    }

    func testInvalidDailyTemperatureRangeIsRejected() {
        let data = forecastData(
            dailyMinimumTemperature: 14,
            dailyMaximumTemperature: 8
        )

        XCTAssertThrowsError(try ForecastBuilder.build(from: data)) { error in
            XCTAssertEqual(error as? WeatherDataError, .invalidDailyWeather)
        }
    }

    func testRepositoryPreservesOrderAndEnforcesFiveCityLimit() throws {
        let suiteName = "MyWeatherTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let repository = CityRepository(defaults: defaults, key: "cities")
        let cities = (1...5).map(makeCity)

        try repository.save(cities)

        XCTAssertEqual(repository.load(), cities)

        let reordered = [cities[3], cities[0], cities[4], cities[1], cities[2]]
        try repository.save(reordered)
        XCTAssertEqual(repository.load(), reordered)

        XCTAssertThrowsError(try repository.save(cities + [makeCity(6)])) { error in
            XCTAssertEqual(error as? CityRepositoryError, .tooManyCities)
        }
        XCTAssertThrowsError(try repository.save([makeCity(1), makeCity(1)])) { error in
            XCTAssertEqual(error as? CityRepositoryError, .duplicateCity)
        }
    }

    func testRepositoryRecoversFromCorruptData() throws {
        let suiteName = "MyWeatherTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Data("not-json".utf8), forKey: "cities")

        XCTAssertEqual(CityRepository(defaults: defaults, key: "cities").load(), [])
    }

    func testRepositoryPersistsAndOverwritesWeatherState() throws {
        let suiteName = "MyWeatherTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let repository = CityRepository(defaults: defaults, key: "cities")
        let firstDate = Date(timeIntervalSince1970: 1_800_000_000)
        let secondDate = Date(timeIntervalSince1970: 1_800_003_600)
        let firstSnapshot = try ForecastBuilder.build(from: forecastData())
        let secondSnapshot = try ForecastBuilder.build(
            from: forecastData(
                dailyWeatherCode: 61,
                dailyPrecipitationProbability: 90,
                dailyMinimumTemperature: 8,
                dailyMaximumTemperature: 14
            )
        )

        XCTAssertEqual(repository.loadWeatherState(), .empty)

        let firstState = StoredWeatherState(
            snapshots: [1: firstSnapshot],
            lastUpdated: firstDate
        )
        try repository.saveWeatherState(firstState)
        XCTAssertEqual(repository.loadWeatherState(), firstState)

        let overwrittenState = StoredWeatherState(
            snapshots: [1: secondSnapshot],
            lastUpdated: secondDate
        )
        try repository.saveWeatherState(overwrittenState)
        XCTAssertEqual(repository.loadWeatherState(), overwrittenState)
    }

    func testRepositoryMigratesPreviouslyStoredLastUpdatedDate() throws {
        let suiteName = "MyWeatherTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        defaults.set(date.timeIntervalSince1970, forKey: "cities.lastUpdated")
        let repository = CityRepository(defaults: defaults, key: "cities")

        XCTAssertEqual(
            repository.loadWeatherState(),
            StoredWeatherState(snapshots: [:], lastUpdated: date)
        )
    }

    func testRepositoryRecoversFromCorruptWeatherState() throws {
        let suiteName = "MyWeatherTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Data("not-json".utf8), forKey: "cities.weatherState.v1")

        XCTAssertEqual(
            CityRepository(defaults: defaults, key: "cities").loadWeatherState(),
            .empty
        )
    }

    private func makeCity(_ id: Int) -> SavedCity {
        SavedCity(
            id: id,
            name: "City \(id)",
            region: "Region",
            country: "Country",
            latitude: Double(id),
            longitude: -Double(id),
            timezone: "UTC"
        )
    }

    private func forecastData(
        dailyWeatherCode: Int = 2,
        dailyPrecipitationProbability: Int? = 70,
        dailyMinimumTemperature: Double = -2,
        dailyMaximumTemperature: Double = 19
    ) -> Data {
        let precipitationProbability: Any = dailyPrecipitationProbability.map { $0 as Any } ?? NSNull()
        let object: [String: Any] = [
            "current": [
                "temperature_2m": 13.6,
                "relative_humidity_2m": 72,
                "weather_code": 2
            ],
            "daily": [
                "time": ["2026-03-08"],
                "temperature_2m_min": [dailyMinimumTemperature],
                "temperature_2m_max": [dailyMaximumTemperature],
                "weather_code": [dailyWeatherCode],
                "precipitation_probability_max": [precipitationProbability]
            ]
        ]
        return try! JSONSerialization.data(withJSONObject: object)
    }
}
