//
//  DataStore.swift
//  ASO
//

import Foundation
import SwiftUI

@MainActor
class DataStore: ObservableObject {
    static let shared = DataStore()

    @Published var trackedApps: [TrackedApp] = []
    @Published var selectedCountry: Country = Country.all[0]
    @Published var isLoading = false
    @Published var error: String?

    private let appsKey = "trackedApps"
    private let countryKey = "selectedCountry"

    private init() {
        loadData()
    }

    // MARK: - Persistence
    private func loadData() {
        if let data = UserDefaults.standard.data(forKey: appsKey),
           let apps = try? JSONDecoder().decode([TrackedApp].self, from: data) {
            self.trackedApps = apps
        }

        if let countryCode = UserDefaults.standard.string(forKey: countryKey),
           let country = Country.country(for: countryCode) {
            self.selectedCountry = country
        }
    }

    private func saveData() {
        if let data = try? JSONEncoder().encode(trackedApps) {
            UserDefaults.standard.set(data, forKey: appsKey)
        }
        UserDefaults.standard.set(selectedCountry.code, forKey: countryKey)
    }

    // MARK: - App Management
    func addApp(_ app: AppStoreApp) {
        guard !trackedApps.contains(where: { $0.trackId == app.trackId }) else { return }
        var trackedApp = TrackedApp(from: app)

        if let rating = app.averageUserRating, let count = app.userRatingCount {
            let snapshot = RatingSnapshot(rating: rating, ratingCount: count)
            trackedApp.ratingSnapshots.append(snapshot)
        }

        trackedApps.append(trackedApp)
        saveData()
    }

    func removeApp(_ app: TrackedApp) {
        trackedApps.removeAll { $0.id == app.id }
        saveData()
    }

    func isTracking(_ appId: Int) -> Bool {
        trackedApps.contains { $0.trackId == appId }
    }

    // MARK: - Keyword Management
    func addKeyword(_ keyword: String, to appId: UUID, countryCode: String) {
        guard let index = trackedApps.firstIndex(where: { $0.id == appId }) else { return }

        let keywordLower = keyword.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keywordLower.isEmpty else { return }
        guard !trackedApps[index].keywords.contains(where: {
            $0.keyword.lowercased() == keywordLower && $0.countryCode == countryCode
        }) else { return }

        let trackedKeyword = TrackedKeyword(keyword: keywordLower, countryCode: countryCode)
        trackedApps[index].keywords.append(trackedKeyword)
        trackedApps[index].lastUpdated = Date()
        saveData()
    }

    func removeKeyword(_ keywordId: UUID, from appId: UUID) {
        guard let appIndex = trackedApps.firstIndex(where: { $0.id == appId }) else { return }
        trackedApps[appIndex].keywords.removeAll { $0.id == keywordId }
        trackedApps[appIndex].lastUpdated = Date()
        saveData()
    }

    func updateKeywordRanking(_ keywordId: UUID, for appId: UUID, rank: Int) {
        guard let appIndex = trackedApps.firstIndex(where: { $0.id == appId }),
              let keywordIndex = trackedApps[appIndex].keywords.firstIndex(where: { $0.id == keywordId }) else {
            return
        }

        let ranking = KeywordRanking(rank: rank)
        trackedApps[appIndex].keywords[keywordIndex].rankings.append(ranking)
        trackedApps[appIndex].lastUpdated = Date()
        saveData()
    }

    // MARK: - Rating Snapshots
    func addRatingSnapshot(to appId: UUID, rating: Double, ratingCount: Int) {
        guard let index = trackedApps.firstIndex(where: { $0.id == appId }) else { return }
        let snapshot = RatingSnapshot(rating: rating, ratingCount: ratingCount)
        trackedApps[index].ratingSnapshots.append(snapshot)
        trackedApps[index].lastUpdated = Date()
        saveData()
    }

    // MARK: - Refresh All Rankings
    func refreshAllRankings() async {
        isLoading = true
        error = nil

        for appIndex in trackedApps.indices {
            let app = trackedApps[appIndex]

            for keywordIndex in app.keywords.indices {
                let keyword = app.keywords[keywordIndex]

                do {
                    if let rank = try await AppStoreService.shared.searchKeywordRanking(
                        keyword: keyword.keyword,
                        appId: app.trackId,
                        country: keyword.countryCode
                    ) {
                        let ranking = KeywordRanking(rank: rank)
                        trackedApps[appIndex].keywords[keywordIndex].rankings.append(ranking)
                    }
                } catch {
                    self.error = error.localizedDescription
                }

                try? await Task.sleep(nanoseconds: 500_000_000)
            }

            if let updatedApp = try? await AppStoreService.shared.lookupApp(id: app.trackId, country: selectedCountry.code) {
                if let rating = updatedApp.averageUserRating, let count = updatedApp.userRatingCount {
                    let snapshot = RatingSnapshot(rating: rating, ratingCount: count)
                    trackedApps[appIndex].ratingSnapshots.append(snapshot)
                }
            }
        }

        for index in trackedApps.indices {
            trackedApps[index].lastUpdated = Date()
        }

        saveData()
        isLoading = false
    }

    // MARK: - Country
    func setCountry(_ country: Country) {
        selectedCountry = country
        saveData()
    }

    // MARK: - Statistics
    var totalKeywords: Int {
        trackedApps.reduce(0) { $0 + $1.keywords.count }
    }

    var averageRating: Double? {
        let ratings = trackedApps.compactMap { $0.ratingSnapshots.last?.rating }
        guard !ratings.isEmpty else { return nil }
        return ratings.reduce(0, +) / Double(ratings.count)
    }

    var totalReviews: Int {
        trackedApps.compactMap { $0.ratingSnapshots.last?.ratingCount }.reduce(0, +)
    }
}
