import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol WeatherServing: Sendable {
    func searchCities(query: String) async throws -> [SavedCity]
    func fetchToday(for city: SavedCity) async throws -> WeatherSnapshot
}

public enum WeatherServiceError: LocalizedError {
    case invalidURL
    case unsuccessfulResponse

    public var errorDescription: String? {
        switch self {
        case .invalidURL: "The weather request could not be created."
        case .unsuccessfulResponse: "The weather service could not be reached."
        }
    }
}

public struct OpenMeteoWeatherService: WeatherServing {
    private static let geocodingHost = "geocoding-api.open-meteo.com"
    private static let forecastHost = "api.open-meteo.com"
    private static let maximumResponseSize = 1_048_576

    private let session: URLSession

    public init(session: URLSession? = nil) {
        self.session = session ?? Self.makeSession()
    }

    public func searchCities(query: String) async throws -> [SavedCity] {
        let cleanedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanedQuery.count >= 2 else { return [] }

        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")
        components?.queryItems = [
            URLQueryItem(name: "name", value: cleanedQuery),
            URLQueryItem(name: "count", value: "10"),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = components?.url else { throw WeatherServiceError.invalidURL }

        let data = try await request(url, expectedHost: Self.geocodingHost)
        let response = try JSONDecoder().decode(GeocodingResponse.self, from: data)
        var seenIDs = Set<Int>()

        return (response.results ?? []).compactMap { result in
            guard result.featureCode.hasPrefix("P"), seenIDs.insert(result.id).inserted else {
                return nil
            }
            return SavedCity(
                id: result.id,
                name: result.name,
                region: result.region ?? "",
                country: result.country ?? result.countryCode ?? "",
                latitude: result.latitude,
                longitude: result.longitude,
                timezone: result.timezone
            )
        }
    }

    public func fetchToday(for city: SavedCity) async throws -> WeatherSnapshot {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(city.latitude)),
            URLQueryItem(name: "longitude", value: String(city.longitude)),
            URLQueryItem(name: "timezone", value: city.timezone),
            URLQueryItem(name: "forecast_days", value: "1"),
            URLQueryItem(name: "temperature_unit", value: "celsius"),
            URLQueryItem(name: "current", value: "temperature_2m,relative_humidity_2m,weather_code"),
            URLQueryItem(
                name: "daily",
                value: "temperature_2m_min,temperature_2m_max,weather_code,precipitation_probability_max"
            )
        ]
        guard let url = components?.url else { throw WeatherServiceError.invalidURL }

        return try ForecastBuilder.build(
            from: await request(url, expectedHost: Self.forecastHost)
        )
    }

    private func request(_ url: URL, expectedHost: String) async throws -> Data {
        guard Self.isTrusted(url, expectedHost: expectedHost) else {
            throw WeatherServiceError.invalidURL
        }

        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 15
        )
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              let responseURL = httpResponse.url,
              Self.isTrusted(responseURL, expectedHost: expectedHost),
              httpResponse.mimeType?.lowercased() == "application/json",
              httpResponse.expectedContentLength <= Int64(Self.maximumResponseSize),
              data.count <= Self.maximumResponseSize else {
            throw WeatherServiceError.unsuccessfulResponse
        }
        return data
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: configuration)
    }

    private static func isTrusted(_ url: URL, expectedHost: String) -> Bool {
        url.scheme?.lowercased() == "https"
            && url.host?.lowercased() == expectedHost
            && (url.port == nil || url.port == 443)
            && url.user == nil
            && url.password == nil
    }
}

private struct GeocodingResponse: Decodable {
    let results: [GeocodingResult]?
}

private struct GeocodingResult: Decodable {
    let id: Int
    let name: String
    let latitude: Double
    let longitude: Double
    let timezone: String
    let featureCode: String
    let countryCode: String?
    let country: String?
    let region: String?

    enum CodingKeys: String, CodingKey {
        case id, name, latitude, longitude, timezone, country
        case featureCode = "feature_code"
        case countryCode = "country_code"
        case region = "admin1"
    }
}
