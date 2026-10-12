import Foundation

@MainActor
final class WeatherStore: ObservableObject {
    @Published private(set) var cities: [SavedCity]
    @Published private(set) var isRefreshing = false
    @Published private var weatherState: WeatherDisplayState

    private let service: any WeatherServing
    private let repository: CityRepository

    init(
        service: any WeatherServing = OpenMeteoWeatherService(),
        repository: CityRepository = CityRepository()
    ) {
        self.service = service
        self.repository = repository
        let loadedCities = repository.load()
        let storedWeather = repository.loadWeatherState()
        let savedCityIDs = Set(loadedCities.map(\.id))
        let storedSnapshots = storedWeather.snapshots.filter { savedCityIDs.contains($0.key) }
        let storedLastUpdated = loadedCities.isEmpty ? nil : storedWeather.lastUpdated
        self.cities = loadedCities
        self.weatherState = WeatherDisplayState(
            snapshots: storedSnapshots,
            unavailableCityIDs: [],
            lastUpdated: storedLastUpdated
        )

        if storedSnapshots != storedWeather.snapshots || storedLastUpdated != storedWeather.lastUpdated {
            try? repository.saveWeatherState(
                StoredWeatherState(
                    snapshots: storedSnapshots,
                    lastUpdated: storedLastUpdated
                )
            )
        }
    }

    var canAddCity: Bool {
        cities.count < CityRepository.maximumCityCount
    }

    var snapshots: [Int: WeatherSnapshot] {
        weatherState.snapshots
    }

    var unavailableCityIDs: Set<Int> {
        weatherState.unavailableCityIDs
    }

    var lastUpdated: Date? {
        weatherState.lastUpdated
    }

    func contains(_ city: SavedCity) -> Bool {
        cities.contains { $0.id == city.id }
    }

    @discardableResult
    func add(_ city: SavedCity) -> Bool {
        guard canAddCity, !contains(city) else { return false }
        let updated = cities + [city]
        do {
            try repository.save(updated)
            cities = updated
            return true
        } catch {
            return false
        }
    }

    func remove(at offsets: IndexSet) {
        let removedIDs = offsets.compactMap { index in
            cities.indices.contains(index) ? cities[index].id : nil
        }
        let updated = cities.enumerated()
            .filter { !offsets.contains($0.offset) }
            .map(\.element)
        do {
            try repository.save(updated)
            cities = updated
            var updatedWeatherState = weatherState
            for id in removedIDs {
                updatedWeatherState.snapshots[id] = nil
                updatedWeatherState.unavailableCityIDs.remove(id)
            }
            if cities.isEmpty {
                updatedWeatherState.lastUpdated = nil
            }
            weatherState = updatedWeatherState
            persistWeatherState()
        } catch {
            // Keep the visible list consistent with its persisted version.
        }
    }

    func move(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        let validOffsets = offsets.filter { cities.indices.contains($0) }.sorted()
        guard !validOffsets.isEmpty else { return }

        let movingCities = validOffsets.map { cities[$0] }
        var updated = cities
        for index in validOffsets.reversed() {
            updated.remove(at: index)
        }

        let removedBeforeDestination = validOffsets.filter { $0 < destination }.count
        let insertionIndex = min(
            max(0, destination - removedBeforeDestination),
            updated.count
        )
        updated.insert(contentsOf: movingCities, at: insertionIndex)

        do {
            try repository.save(updated)
            cities = updated
        } catch {
            // Keep the visible list consistent with its persisted version.
        }
    }

    func searchCities(_ query: String) async throws -> [SavedCity] {
        try await service.searchCities(query: query)
    }

    func refreshAll() async {
        guard !isRefreshing, !cities.isEmpty else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let service = self.service
        let citiesToFetch = cities
        let results = await withTaskGroup(of: FetchResult.self, returning: [FetchResult].self) { group in
            for city in citiesToFetch {
                group.addTask {
                    do {
                        return FetchResult(
                            cityID: city.id,
                            snapshot: try await service.fetchToday(for: city)
                        )
                    } catch {
                        return FetchResult(cityID: city.id, snapshot: nil)
                    }
                }
            }

            var results: [FetchResult] = []
            results.reserveCapacity(citiesToFetch.count)
            for await result in group {
                results.append(result)
            }
            return results
        }

        let currentCityIDs = Set(cities.map(\.id))
        var updatedWeatherState = weatherState
        var didUpdateWeather = false
        for result in results where currentCityIDs.contains(result.cityID) {
            if let snapshot = result.snapshot {
                updatedWeatherState.snapshots[result.cityID] = snapshot
                updatedWeatherState.unavailableCityIDs.remove(result.cityID)
                didUpdateWeather = true
            } else if updatedWeatherState.snapshots[result.cityID] == nil {
                updatedWeatherState.unavailableCityIDs.insert(result.cityID)
            } else {
                updatedWeatherState.unavailableCityIDs.remove(result.cityID)
            }
        }

        if didUpdateWeather {
            updatedWeatherState.lastUpdated = Date()
        }
        if updatedWeatherState != weatherState {
            weatherState = updatedWeatherState
        }
        if didUpdateWeather {
            persistWeatherState()
        }
    }

    private func persistWeatherState() {
        try? repository.saveWeatherState(
            StoredWeatherState(snapshots: snapshots, lastUpdated: lastUpdated)
        )
    }
}

private struct WeatherDisplayState: Equatable {
    var snapshots: [Int: WeatherSnapshot]
    var unavailableCityIDs: Set<Int>
    var lastUpdated: Date?
}

private struct FetchResult: Sendable {
    let cityID: Int
    let snapshot: WeatherSnapshot?
}
