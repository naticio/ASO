//
//  AppsListView.swift
//  ASO
//

import SwiftUI

struct AppsListView: View {
    @EnvironmentObject var dataStore: DataStore
    @Binding var selectedApp: TrackedApp?
    @Binding var showingAddApp: Bool
    @State private var searchText = ""

    var filteredApps: [TrackedApp] {
        if searchText.isEmpty {
            return dataStore.trackedApps.sorted { $0.lastUpdated > $1.lastUpdated }
        }
        return dataStore.trackedApps.filter {
            $0.trackName.localizedCaseInsensitiveContains(searchText) ||
            $0.sellerName.localizedCaseInsensitiveContains(searchText)
        }.sorted { $0.lastUpdated > $1.lastUpdated }
    }

    var body: some View {
        Group {
            if dataStore.trackedApps.isEmpty {
                emptyState
            } else {
                appsList
            }
        }
        .navigationTitle("Apps")
        .searchable(text: $searchText, prompt: "Search apps")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingAddApp = true }) {
                    Image(systemName: "plus")
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Apps", systemImage: "apps.iphone")
        } description: {
            Text("Add your first app to start tracking keywords and rankings.")
        } actions: {
            Button("Add App") {
                showingAddApp = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var appsList: some View {
        List(selection: $selectedApp) {
            ForEach(filteredApps) { app in
                AppRowView(app: app)
                    .tag(app)
                    .contextMenu {
                        Button(role: .destructive) {
                            dataStore.removeApp(app)
                            if selectedApp?.id == app.id {
                                selectedApp = nil
                            }
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
            }
            .onDelete(perform: deleteApps)
        }
        .listStyle(.inset)
    }

    private func deleteApps(at offsets: IndexSet) {
        for index in offsets {
            let app = filteredApps[index]
            dataStore.removeApp(app)
            if selectedApp?.id == app.id {
                selectedApp = nil
            }
        }
    }
}

// MARK: - App Row View
struct AppRowView: View {
    let app: TrackedApp

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: app.artworkUrl)) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } placeholder: {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.gray.opacity(0.3))
            }
            .frame(width: 44, height: 44)
            .cornerRadius(10)

            VStack(alignment: .leading, spacing: 2) {
                Text(app.trackName)
                    .font(.headline)
                    .lineLimit(1)
                Text(app.sellerName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 4) {
                    Text("\(app.keywords.count)")
                        .font(.caption)
                        .fontWeight(.medium)
                    Image(systemName: "magnifyingglass")
                        .font(.caption2)
                }
                .foregroundColor(.secondary)

                if let lastRating = app.ratingSnapshots.last {
                    HStack(spacing: 2) {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundColor(.yellow)
                        Text(String(format: "%.1f", lastRating.rating))
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - App Search Sheet
struct AppSearchSheet: View {
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) var dismiss
    @State private var searchText = ""
    @State private var searchResults: [AppStoreApp] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Country Selector
                HStack {
                    Text("Country:")
                        .foregroundColor(.secondary)
                    Picker("Country", selection: $dataStore.selectedCountry) {
                        ForEach(Country.all) { country in
                            Text("\(country.flag) \(country.name)")
                                .tag(country)
                        }
                    }
                    .pickerStyle(.menu)
                    Spacer()
                }
                .padding()

                Divider()

                // Results
                if isSearching {
                    ProgressView("Searching...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorMessage {
                    ContentUnavailableView {
                        Label("Error", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    }
                } else if searchResults.isEmpty && !searchText.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else if searchResults.isEmpty {
                    ContentUnavailableView {
                        Label("Search Apps", systemImage: "magnifyingglass")
                    } description: {
                        Text("Search for apps by name or developer to add them to your tracking list.")
                    }
                } else {
                    List(searchResults) { app in
                        SearchResultRow(app: app, isTracked: dataStore.isTracking(app.trackId)) {
                            dataStore.addApp(app)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Add App")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .searchable(text: $searchText, prompt: "Search App Store")
            .onChange(of: searchText) { _, newValue in
                searchTask?.cancel()
                searchTask = Task {
                    await performSearch(query: newValue)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 600)
        #endif
    }

    private func performSearch(query: String) async {
        guard !query.isEmpty else {
            searchResults = []
            return
        }

        guard query.count >= 2 else { return }

        try? await Task.sleep(nanoseconds: 300_000_000)

        guard !Task.isCancelled else { return }

        isSearching = true
        errorMessage = nil

        do {
            let results = try await AppStoreService.shared.searchApps(
                query: query,
                country: dataStore.selectedCountry.code
            )
            if !Task.isCancelled {
                searchResults = results
            }
        } catch {
            if !Task.isCancelled {
                errorMessage = error.localizedDescription
            }
        }

        if !Task.isCancelled {
            isSearching = false
        }
    }
}

// MARK: - Search Result Row
struct SearchResultRow: View {
    let app: AppStoreApp
    let isTracked: Bool
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: app.artworkUrl100)) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } placeholder: {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.gray.opacity(0.3))
            }
            .frame(width: 50, height: 50)
            .cornerRadius(10)

            VStack(alignment: .leading, spacing: 2) {
                Text(app.trackName)
                    .font(.headline)
                    .lineLimit(1)
                Text(app.sellerName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(app.primaryGenreName)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(4)

                    if let rating = app.averageUserRating {
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundColor(.yellow)
                            Text(String(format: "%.1f", rating))
                                .font(.caption)
                            Text("(\(app.formattedRatingCount))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Spacer()

            if isTracked {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title2)
            } else {
                Button(action: onAdd) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .foregroundColor(.blue)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    AppsListView(selectedApp: .constant(nil), showingAddApp: .constant(false))
        .environmentObject(DataStore.shared)
}
