import Foundation

public struct SavedCity: Codable, Identifiable, Equatable, Hashable, Sendable {
    public let id: Int
    public let name: String
    public let region: String
    public let country: String
    public let latitude: Double
    public let longitude: Double
    public let timezone: String

    public init(
        id: Int,
        name: String,
        region: String,
        country: String,
        latitude: Double,
        longitude: Double,
        timezone: String
    ) {
        self.id = id
        self.name = name
        self.region = region
        self.country = country
        self.latitude = latitude
        self.longitude = longitude
        self.timezone = timezone
    }

    public var subtitle: String {
        [region, country]
            .filter { !$0.isEmpty && $0.caseInsensitiveCompare(name) != .orderedSame }
            .reduce(into: [String]()) { parts, value in
                if !parts.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) {
                    parts.append(value)
                }
            }
            .joined(separator: ", ")
    }
}

public enum WeatherCondition: String, Codable, CaseIterable, Sendable {
    case clear = "Clear"
    case cloudy = "Cloudy"
    case fog = "Fog"
    case drizzle = "Drizzle"
    case rain = "Rain"
    case snow = "Snow"
    case thunderstorm = "Thunderstorm"
    case unknown = "Unknown"

    public init(wmoCode: Int) {
        switch wmoCode {
        case 0: self = .clear
        case 1...3: self = .cloudy
        case 45, 48: self = .fog
        case 51...57: self = .drizzle
        case 61...67, 80...82: self = .rain
        case 71...77, 85, 86: self = .snow
        case 95...99: self = .thunderstorm
        default: self = .unknown
        }
    }
}

public struct CurrentWeather: Codable, Equatable, Sendable {
    public let temperature: Double
    public let humidity: Int
    public let condition: WeatherCondition

    public init(temperature: Double, humidity: Int, condition: WeatherCondition) {
        self.temperature = temperature
        self.humidity = humidity
        self.condition = condition
    }
}

public enum WholeDayCondition: String, Codable, CaseIterable, Sendable {
    case sunny = "Sunny"
    case sunCloudMix = "Mix of Sun and Clouds"
    case cloudy = "Cloudy"
    case fog = "Fog"
    case drizzle = "Drizzle"
    case freezingDrizzle = "Freezing Drizzle"
    case rain = "Rain"
    case freezingRain = "Freezing Rain"
    case showers = "Showers"
    case snow = "Snow"
    case snowShowers = "Snow Showers"
    case thunderstorm = "Thunderstorm"
    case unknown = "Unknown"

    public init(wmoCode: Int) {
        switch wmoCode {
        case 0, 1: self = .sunny
        case 2: self = .sunCloudMix
        case 3: self = .cloudy
        case 45, 48: self = .fog
        case 51, 53, 55: self = .drizzle
        case 56, 57: self = .freezingDrizzle
        case 61, 63, 65: self = .rain
        case 66, 67: self = .freezingRain
        case 80...82: self = .showers
        case 71...77: self = .snow
        case 85, 86: self = .snowShowers
        case 95...99: self = .thunderstorm
        default: self = .unknown
        }
    }
}

public enum PrecipitationKind: String, Codable, CaseIterable, Sendable {
    case precipitation = "Precipitation"
    case drizzle = "Drizzle"
    case freezingDrizzle = "Freezing Drizzle"
    case rain = "Rain"
    case freezingRain = "Freezing Rain"
    case showers = "Showers"
    case snow = "Snow"
    case snowShowers = "Snow Showers"
    case thunderstorm = "Thunderstorm"

    init?(wmoCode: Int) {
        switch wmoCode {
        case 51, 53, 55: self = .drizzle
        case 56, 57: self = .freezingDrizzle
        case 61, 63, 65: self = .rain
        case 66, 67: self = .freezingRain
        case 80...82: self = .showers
        case 71...77: self = .snow
        case 85, 86: self = .snowShowers
        case 95...99: self = .thunderstorm
        default: return nil
        }
    }
}

public struct PrecipitationChance: Codable, Equatable, Sendable {
    public let kind: PrecipitationKind
    public let probability: Int?

    public var label: String {
        if kind == .precipitation {
            guard let probability else { return "Chance of precipitation —" }
            return "Chance of precipitation \(probability)%"
        }

        guard let probability else { return "\(kind.rawValue) —" }
        return "\(kind.rawValue) \(probability)%"
    }

    public init(kind: PrecipitationKind, probability: Int?) {
        self.kind = kind
        self.probability = probability
    }
}

public struct TodayForecast: Codable, Equatable, Sendable {
    public let minimumTemperature: Double
    public let maximumTemperature: Double
    public let condition: WholeDayCondition
    public let precipitation: PrecipitationChance

    public init(
        minimumTemperature: Double,
        maximumTemperature: Double,
        condition: WholeDayCondition,
        precipitation: PrecipitationChance
    ) {
        self.minimumTemperature = minimumTemperature
        self.maximumTemperature = maximumTemperature
        self.condition = condition
        self.precipitation = precipitation
    }
}

public struct WeatherSnapshot: Codable, Equatable, Sendable {
    public let current: CurrentWeather
    public let today: TodayForecast

    public init(current: CurrentWeather, today: TodayForecast) {
        self.current = current
        self.today = today
    }
}
