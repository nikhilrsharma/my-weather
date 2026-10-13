import SwiftUI

struct AddCityView: View {
    @EnvironmentObject private var store: WeatherStore
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [SavedCity] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var searchFieldIsFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    TextField("City Name", text: $query)
                        .font(.weatherBody)
                        .weatherCityTextInput()
                        .submitLabel(.search)
                        .focused($searchFieldIsFocused)
                        .disabled(!store.canAddCity)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(.secondary.opacity(0.16), in: RoundedRectangle(cornerRadius: 10))

                    if !query.isEmpty {
                        Button("Clear") {
                            query = ""
                        }
                        .font(.weatherSubheadline)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                Divider()

                List {
                    if !store.canAddCity {
                        Text("Remove a city before adding another.")
                            .foregroundStyle(.secondary)
                    } else if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.secondary)
                    } else if isSearching {
                        Text("Searching")
                            .foregroundStyle(.secondary)
                    } else if query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 {
                        Text("Type at least 2 characters")
                            .foregroundStyle(.secondary)
                    } else if results.isEmpty {
                        Text("No Results")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(results) { city in
                            Button {
                                if store.add(city) {
                                    dismiss()
                                    Task { await store.refreshAll() }
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(city.name)
                                        .font(.weatherBody)
                                        .foregroundStyle(.primary)
                                    if !city.subtitle.isEmpty {
                                        Text(city.subtitle)
                                            .font(.weatherSubheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                    if store.contains(city) {
                                        Text("Already Added")
                                            .font(.weatherFootnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 3)
                            }
                            .disabled(store.contains(city) || store.isRefreshing)
                        }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("")
            .weatherInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Add City")
                        .font(.weatherHeadline)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onChange(of: query) { _, newValue in
                scheduleSearch(for: newValue)
            }
            .onDisappear {
                searchTask?.cancel()
            }
            .task {
                if store.canAddCity {
                    searchFieldIsFocused = true
                }
            }
        }
        .font(.weatherBody)
    }

    private func scheduleSearch(for value: String) {
        searchTask?.cancel()
        errorMessage = nil
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count >= 2, store.canAddCity else {
            results = []
            isSearching = false
            return
        }

        isSearching = true
        searchTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(300))
                let matches = try await store.searchCities(cleaned)
                guard !Task.isCancelled else { return }
                results = matches
                isSearching = false
            } catch is CancellationError {
                // A newer query replaced this one.
            } catch {
                guard !Task.isCancelled else { return }
                results = []
                isSearching = false
                errorMessage = "Search Unavailable"
            }
        }
    }
}
