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
}

struct CurrentResponse: Decodable {
    let temperature: Double
    let humidity: Int
    let weatherCode: Int

    enum CodingKeys: String, CodingKey {
        case temperature = "temperature_2m"
        case humidity = "relative_humidity_2m"
        case weatherCode = "weather_code"
    }
}

struct DailyResponse: Decodable {
    let time: [String]
    let minimumTemperatures: [Double]
    let maximumTemperatures: [Double]
    let weatherCodes: [Int]
    let precipitationProbabilities: [Int?]

    enum CodingKeys: String, CodingKey {
        case time
        case minimumTemperatures = "temperature_2m_min"
        case maximumTemperatures = "temperature_2m_max"
        case weatherCodes = "weather_code"
        case precipitationProbabilities = "precipitation_probability_max"
    }
}

public enum ForecastBuilder {
    public static func build(from data: Data) throws -> WeatherSnapshot {
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
              }),
              daily.minimumTemperatures[0] <= daily.maximumTemperatures[0] else {
            throw WeatherDataError.invalidDailyWeather
        }

        let current = CurrentWeather(
            temperature: response.current.temperature,
            humidity: response.current.humidity,
            condition: WeatherCondition(wmoCode: response.current.weatherCode)
        )

        let today = TodayForecast(
            minimumTemperature: daily.minimumTemperatures[0],
            maximumTemperature: daily.maximumTemperatures[0],
            condition: WholeDayCondition(wmoCode: daily.weatherCodes[0]),
            precipitation: precipitationChance(daily: daily)
        )

        return WeatherSnapshot(current: current, today: today)
    }

    private static func precipitationChance(daily: DailyResponse) -> PrecipitationChance {
        PrecipitationChance(
            kind: PrecipitationKind(wmoCode: daily.weatherCodes[0]) ?? .precipitation,
            probability: daily.precipitationProbabilities[0]
        )
    }
}
