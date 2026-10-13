import Foundation

public enum WeatherDataError: LocalizedError, Equatable {
    case invalidResponse
    case invalidCurrentWeather
    case invalidDailyWeather

    public var errorDescription: String? {
        switch self {
        case .invalidResponse: "The weather service returned an invalid response."
        case .invalidCurrentWeather: "Current weather data is unavailable."
        case .invalidDailyWeather: "Today’s weather data is unavailable."
        }
    }
}

struct ForecastResponse: Decodable {
    let current: CurrentResponse
    let daily: DailyResponse
    let timezone: String?
    let utcOffsetSeconds: Int?
    let hourly: HourlyResponse?

    enum CodingKeys: String, CodingKey {
        case current, daily, timezone, hourly
        case utcOffsetSeconds = "utc_offset_seconds"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        current = try values.decode(CurrentResponse.self, forKey: .current)
        daily = try values.decode(DailyResponse.self, forKey: .daily)
        timezone = try values.decodeIfPresent(String.self, forKey: .timezone)
        utcOffsetSeconds = try values.decodeIfPresent(Int.self, forKey: .utcOffsetSeconds)
        // A malformed optional chart must not hide otherwise usable weather.
        hourly = try? values.decodeIfPresent(HourlyResponse.self, forKey: .hourly)
    }
}

struct CurrentResponse: Decodable {
    let time: ForecastTime?
    let temperature: Double
    let humidity: Int
    let weatherCode: Int

    enum CodingKeys: String, CodingKey {
        case time
        case temperature = "temperature_2m"
        case humidity = "relative_humidity_2m"
        case weatherCode = "weather_code"
    }
}

struct DailyResponse: Decodable {
    let time: [ForecastTime]
    let minimumTemperatures: [Double]
    let maximumTemperatures: [Double]
    let weatherCodes: [Int]
    let precipitationProbabilities: [Int?]
    let sunrise: [ForecastTime?]?
    let sunset: [ForecastTime?]?

    enum CodingKeys: String, CodingKey {
        case time, sunrise, sunset
        case minimumTemperatures = "temperature_2m_min"
        case maximumTemperatures = "temperature_2m_max"
        case weatherCodes = "weather_code"
        case precipitationProbabilities = "precipitation_probability_max"
    }
}

public enum ForecastBuilder {
    public static func build(from data: Data, timezone requestedTimezone: String? = nil) throws -> WeatherSnapshot {
        let response: ForecastResponse
        do {
            response = try JSONDecoder().decode(ForecastResponse.self, from: data)
        } catch {
            throw WeatherDataError.invalidResponse
        }

        guard response.current.temperature.isFinite,
              (0...100).contains(response.current.humidity) else {
            throw WeatherDataError.invalidCurrentWeather
        }

        let daily = response.daily
        guard !daily.time.isEmpty,
              daily.time.count == daily.minimumTemperatures.count,
              daily.time.count == daily.maximumTemperatures.count,
              daily.time.count == daily.weatherCodes.count,
              daily.time.count == daily.precipitationProbabilities.count,
              daily.minimumTemperatures.allSatisfy(\.isFinite),
              daily.maximumTemperatures.allSatisfy(\.isFinite),
              daily.precipitationProbabilities.allSatisfy({ probability in
                  probability.map { (0...100).contains($0) } ?? true
              }) else {
            throw WeatherDataError.invalidDailyWeather
        }

        let timezone = TimeZone(identifier: requestedTimezone ?? response.timezone ?? "UTC") ?? TimeZone(secondsFromGMT: 0)!
        let index = try dailyIndex(response: response, timezone: timezone)
        guard daily.minimumTemperatures[index] <= daily.maximumTemperatures[index] else {
            throw WeatherDataError.invalidDailyWeather
        }

        let current = CurrentWeather(
            temperature: response.current.temperature,
            humidity: response.current.humidity,
            condition: WeatherCondition(wmoCode: response.current.weatherCode)
        )

        let today = TodayForecast(
            minimumTemperature: daily.minimumTemperatures[index],
            maximumTemperature: daily.maximumTemperatures[index],
            condition: WholeDayCondition(wmoCode: daily.weatherCodes[index]),
            precipitation: precipitationChance(daily: daily, index: index)
        )

        return WeatherSnapshot(
            current: current, today: today,
            dayTimeline: DayTimelineBuilder.build(response: response, dailyIndex: index, timezone: timezone)
        )
    }

    private static func dailyIndex(response: ForecastResponse, timezone: TimeZone) throws -> Int {
        guard let currentDate = response.current.time?.date(in: timezone) else { return 0 }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timezone
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: currentDate)
        // Open-Meteo's daily boundaries use the offset at request time, even on
        // DST days. Hourly timestamps below are converted with the city's zone.
        formatter.timeZone = TimeZone(secondsFromGMT: response.utcOffsetSeconds ?? timezone.secondsFromGMT(for: currentDate))
        guard let index = response.daily.time.firstIndex(where: { value in
            switch value {
            case .iso(let string): return String(string.prefix(10)) == today
            case .unix:
                return value.date(in: timezone).map { formatter.string(from: $0) == today } ?? false
            }
        }) else { throw WeatherDataError.invalidDailyWeather }
        return index
    }

    private static func precipitationChance(daily: DailyResponse, index: Int) -> PrecipitationChance {
        PrecipitationChance(
            kind: PrecipitationKind(wmoCode: daily.weatherCodes[index]) ?? .precipitation,
            probability: daily.precipitationProbabilities[index]
        )
    }
}
