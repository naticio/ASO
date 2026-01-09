//
//  SettingsView.swift
//  ASO
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var dataStore: DataStore
    @State private var showingDeleteConfirmation = false
    @State private var showingExportSheet = false
    @AppStorage("autoRefreshEnabled") private var autoRefreshEnabled = false
    @AppStorage("refreshInterval") private var refreshInterval = 24
    @AppStorage("notificationsEnabled") private var notificationsEnabled = false

    var body: some View {
        Form {
            // Default Country
            Section {
                Picker("Default Country", selection: $dataStore.selectedCountry) {
                    ForEach(Country.all) { country in
                        Text("\(country.flag) \(country.name)")
                            .tag(country)
                    }
                }
            } header: {
                Text("App Store")
            } footer: {
                Text("The default country used when searching for apps and tracking keywords.")
            }

            // Refresh Settings
            Section {
                Toggle("Auto Refresh", isOn: $autoRefreshEnabled)

                if autoRefreshEnabled {
                    Picker("Refresh Interval", selection: $refreshInterval) {
                        Text("Every 6 hours").tag(6)
                        Text("Every 12 hours").tag(12)
                        Text("Every 24 hours").tag(24)
                        Text("Every 48 hours").tag(48)
                    }
                }
            } header: {
                Text("Data Refresh")
            } footer: {
                Text("Automatically refresh keyword rankings and app ratings at the specified interval.")
            }

            // Notifications
            Section {
                Toggle("Enable Notifications", isOn: $notificationsEnabled)
            } header: {
                Text("Notifications")
            } footer: {
                Text("Receive notifications when keyword rankings change significantly.")
            }

            // Data Management
            Section {
                Button(action: { showingExportSheet = true }) {
                    Label("Export Data", systemImage: "square.and.arrow.up")
                }

                Button(role: .destructive, action: { showingDeleteConfirmation = true }) {
                    Label("Delete All Data", systemImage: "trash")
                }
            } header: {
                Text("Data Management")
            }

            // Statistics
            Section {
                HStack {
                    Text("Tracked Apps")
                    Spacer()
                    Text("\(dataStore.trackedApps.count)")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Total Keywords")
                    Spacer()
                    Text("\(dataStore.totalKeywords)")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Countries")
                    Spacer()
                    Text("\(uniqueCountries)")
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Statistics")
            }

            // About
            Section {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0.0")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Build")
                    Spacer()
                    Text("1")
                        .foregroundColor(.secondary)
                }

                Link(destination: URL(string: "https://apple.com")!) {
                    HStack {
                        Text("App Store API")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                    }
                }
            } header: {
                Text("About")
            } footer: {
                Text("ASO uses the official iTunes Search API to retrieve app information and reviews.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .alert("Delete All Data", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteAllData()
            }
        } message: {
            Text("This will permanently delete all tracked apps, keywords, and historical data. This action cannot be undone.")
        }
        .sheet(isPresented: $showingExportSheet) {
            ExportSheet()
        }
    }

    private var uniqueCountries: Int {
        var countries = Set<String>()
        for app in dataStore.trackedApps {
            for keyword in app.keywords {
                countries.insert(keyword.countryCode)
            }
        }
        return countries.count
    }

    private func deleteAllData() {
        dataStore.trackedApps.removeAll()
        UserDefaults.standard.removeObject(forKey: "trackedApps")
    }
}

// MARK: - Export Sheet
struct ExportSheet: View {
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) var dismiss
    @State private var exportFormat: ExportFormat = .json
    @State private var exportedURL: URL?

    enum ExportFormat: String, CaseIterable {
        case json = "JSON"
        case csv = "CSV"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Format") {
                    Picker("Export Format", selection: $exportFormat) {
                        ForEach(ExportFormat.allCases, id: \.self) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Preview") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Data to Export:")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text("• \(dataStore.trackedApps.count) Apps")
                        Text("• \(dataStore.totalKeywords) Keywords")
                        Text("• \(totalRankings) Rankings")
                        Text("• \(totalSnapshots) Rating Snapshots")
                    }
                    .font(.subheadline)
                }

                Section {
                    Button(action: exportData) {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Export Data")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(width: 400, height: 350)
        #endif
    }

    private var totalRankings: Int {
        dataStore.trackedApps.reduce(0) { sum, app in
            sum + app.keywords.reduce(0) { $0 + $1.rankings.count }
        }
    }

    private var totalSnapshots: Int {
        dataStore.trackedApps.reduce(0) { $0 + $1.ratingSnapshots.count }
    }

    private func exportData() {
        switch exportFormat {
        case .json:
            exportJSON()
        case .csv:
            exportCSV()
        }
    }

    private func exportJSON() {
        guard let data = try? JSONEncoder().encode(dataStore.trackedApps),
              let jsonString = String(data: data, encoding: .utf8) else {
            return
        }

        #if os(macOS)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "aso_export.json"

        if panel.runModal() == .OK, let url = panel.url {
            try? jsonString.write(to: url, atomically: true, encoding: .utf8)
        }
        #else
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("aso_export.json")
        try? jsonString.write(to: tempURL, atomically: true, encoding: .utf8)
        exportedURL = tempURL
        #endif

        dismiss()
    }

    private func exportCSV() {
        var csv = "App Name,Bundle ID,Keyword,Country,Current Rank,Popularity,Difficulty,Last Updated\n"

        for app in dataStore.trackedApps {
            for keyword in app.keywords {
                let rank = keyword.currentRank.map { String($0) } ?? "N/A"
                let country = Country.country(for: keyword.countryCode)?.name ?? keyword.countryCode
                csv += "\"\(app.trackName)\",\(app.bundleId),\"\(keyword.keyword)\",\(country),\(rank),\(keyword.popularity),\(keyword.difficulty),\(keyword.dateAdded)\n"
            }
        }

        #if os(macOS)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "aso_export.csv"

        if panel.runModal() == .OK, let url = panel.url {
            try? csv.write(to: url, atomically: true, encoding: .utf8)
        }
        #else
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("aso_export.csv")
        try? csv.write(to: tempURL, atomically: true, encoding: .utf8)
        exportedURL = tempURL
        #endif

        dismiss()
    }
}

#Preview {
    SettingsView()
        .environmentObject(DataStore.shared)
}
