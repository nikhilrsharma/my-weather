import Foundation

public enum CityRepositoryError: LocalizedError, Equatable {
    case tooManyCities
    case duplicateCity
    case encodingFailed

    public var errorDescription: String? {
        switch self {
        case .tooManyCities: "A maximum of five cities can be saved."
        case .duplicateCity: "That city is already in the list."
        case .encodingFailed: "The city list could not be saved."
        }
    }
}

struct StoredWeatherState: Codable, Equatable, Sendable {
    let snapshots: [Int: WeatherSnapshot]
    let lastUpdated: Date?

    static let empty = StoredWeatherState(snapshots: [:], lastUpdated: nil)
}

public final class CityRepository {
    public static let maximumCityCount = 5

    private let defaults: UserDefaults
    private let key: String

    private var legacyLastUpdatedKey: String {
        "\(key).lastUpdated"
    }

    private var weatherStateKey: String {
        "\(key).weatherState.v1"
    }

    public init(defaults: UserDefaults = .standard, key: String = "savedCities") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> [SavedCity] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([SavedCity].self, from: data) else {
            return []
        }

        var seenIDs = Set<Int>()
        return decoded
            .filter { seenIDs.insert($0.id).inserted }
            .prefix(Self.maximumCityCount)
            .map { $0 }
    }

    public func save(_ cities: [SavedCity]) throws {
        guard cities.count <= Self.maximumCityCount else {
            throw CityRepositoryError.tooManyCities
        }
        guard Set(cities.map(\.id)).count == cities.count else {
            throw CityRepositoryError.duplicateCity
        }
        guard let data = try? JSONEncoder().encode(cities) else {
            throw CityRepositoryError.encodingFailed
        }
        defaults.set(data, forKey: key)
    }

    func loadWeatherState() -> StoredWeatherState {
        if let data = defaults.data(forKey: weatherStateKey),
           let state = try? JSONDecoder().decode(StoredWeatherState.self, from: data) {
            return state
        }

        guard defaults.object(forKey: legacyLastUpdatedKey) != nil else {
            return .empty
        }
        let timestamp = defaults.double(forKey: legacyLastUpdatedKey)
        guard timestamp > 0 else { return .empty }
        return StoredWeatherState(
            snapshots: [:],
            lastUpdated: Date(timeIntervalSince1970: timestamp)
        )
    }

    func saveWeatherState(_ state: StoredWeatherState) throws {
        guard state.snapshots.count <= Self.maximumCityCount else {
            throw CityRepositoryError.tooManyCities
        }
        guard let data = try? JSONEncoder().encode(state) else {
            throw CityRepositoryError.encodingFailed
        }
        defaults.set(data, forKey: weatherStateKey)
        defaults.removeObject(forKey: legacyLastUpdatedKey)
    }
}
