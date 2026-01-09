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
    @Published var isSyncing = false
    @Published var error: String?
    @Published var lastSyncDate: Date?

    private let appsKey = "trackedApps"
    private let countryKey = "selectedCountry"
    private let lastSyncKey = "lastSyncDate"

    private let iCloud = NSUbiquitousKeyValueStore.default
    private let localStorage = UserDefaults.standard

    private init() {
        setupiCloudObserver()
        loadData()
        syncFromiCloud()
    }

    // MARK: - iCloud Observer
    private func setupiCloudObserver() {
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: iCloud,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleiCloudChange(notification)
            }
        }

        // Start iCloud sync
        iCloud.synchronize()
    }

    private func handleiCloudChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let changeReason = userInfo[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int else {
            return
        }

        switch changeReason {
        case NSUbiquitousKeyValueStoreServerChange,
             NSUbiquitousKeyValueStoreInitialSyncChange:
            // Data changed on another device, merge it
            syncFromiCloud()
        case NSUbiquitousKeyValueStoreQuotaViolationChange:
            error = "iCloud storage quota exceeded"
        case NSUbiquitousKeyValueStoreAccountChange:
            // Account changed, reload data
            syncFromiCloud()
        default:
            break
        }
    }

    // MARK: - Load Data
    private func loadData() {
        // First try to load from local storage
        if let data = localStorage.data(forKey: appsKey),
           let apps = try? JSONDecoder().decode([TrackedApp].self, from: data) {
            self.trackedApps = apps
        }

        if let countryCode = localStorage.string(forKey: countryKey),
           let country = Country.country(for: countryCode) {
            self.selectedCountry = country
        }

        if let syncDate = localStorage.object(forKey: lastSyncKey) as? Date {
            self.lastSyncDate = syncDate
        }
    }

    // MARK: - Sync from iCloud
    func syncFromiCloud() {
        isSyncing = true

        // Get data from iCloud
        if let cloudData = iCloud.data(forKey: appsKey),
           let cloudApps = try? JSONDecoder().decode([TrackedApp].self, from: cloudData) {

            // Merge cloud data with local data
            let mergedApps = mergeApps(local: trackedApps, cloud: cloudApps)
            trackedApps = mergedApps

            // Save merged data back to local and cloud
            saveToLocal()
            saveToiCloud()
        }

        if let countryCode = iCloud.string(forKey: countryKey),
           let country = Country.country(for: countryCode) {
            self.selectedCountry = country
        }

        lastSyncDate = Date()
        localStorage.set(lastSyncDate, forKey: lastSyncKey)
        isSyncing = false
    }

    // MARK: - Merge Logic
    private func mergeApps(local: [TrackedApp], cloud: [TrackedApp]) -> [TrackedApp] {
        var merged: [TrackedApp] = []
        var processedIds = Set<Int>()

        // Process all local apps
        for localApp in local {
            processedIds.insert(localApp.trackId)

            if let cloudApp = cloud.first(where: { $0.trackId == localApp.trackId }) {
                // App exists in both - merge keywords and keep the most recent data
                var mergedApp = localApp.lastUpdated > cloudApp.lastUpdated ? localApp : cloudApp
                mergedApp.keywords = mergeKeywords(local: localApp.keywords, cloud: cloudApp.keywords)
                mergedApp.ratingSnapshots = mergeSnapshots(local: localApp.ratingSnapshots, cloud: cloudApp.ratingSnapshots)
                merged.append(mergedApp)
            } else {
                // Only in local
                merged.append(localApp)
            }
        }

        // Add apps that only exist in cloud
        for cloudApp in cloud where !processedIds.contains(cloudApp.trackId) {
            merged.append(cloudApp)
        }

        return merged.sorted { $0.lastUpdated > $1.lastUpdated }
    }

    private func mergeKeywords(local: [TrackedKeyword], cloud: [TrackedKeyword]) -> [TrackedKeyword] {
        var merged: [TrackedKeyword] = []
        var processedIds = Set<UUID>()

        for localKeyword in local {
            processedIds.insert(localKeyword.id)

            if let cloudKeyword = cloud.first(where: { $0.id == localKeyword.id }) {
                // Merge rankings
                var mergedKeyword = localKeyword
                let allRankings = Set(localKeyword.rankings.map { $0.id }).union(cloudKeyword.rankings.map { $0.id })
                let localRankingsDict = Dictionary(uniqueKeysWithValues: localKeyword.rankings.map { ($0.id, $0) })
                let cloudRankingsDict = Dictionary(uniqueKeysWithValues: cloudKeyword.rankings.map { ($0.id, $0) })

                mergedKeyword.rankings = allRankings.compactMap { id in
                    localRankingsDict[id] ?? cloudRankingsDict[id]
                }.sorted { $0.date < $1.date }

                merged.append(mergedKeyword)
            } else {
                merged.append(localKeyword)
            }
        }

        // Add keywords only in cloud
        for cloudKeyword in cloud where !processedIds.contains(cloudKeyword.id) {
            merged.append(cloudKeyword)
        }

        return merged
    }

    private func mergeSnapshots(local: [RatingSnapshot], cloud: [RatingSnapshot]) -> [RatingSnapshot] {
        let allIds = Set(local.map { $0.id }).union(cloud.map { $0.id })
        let localDict = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        let cloudDict = Dictionary(uniqueKeysWithValues: cloud.map { ($0.id, $0) })

        return allIds.compactMap { id in
            localDict[id] ?? cloudDict[id]
        }.sorted { $0.date < $1.date }
    }

    // MARK: - Save Data
    private func saveData() {
        saveToLocal()
        saveToiCloud()
    }

    private func saveToLocal() {
        if let data = try? JSONEncoder().encode(trackedApps) {
            localStorage.set(data, forKey: appsKey)
        }
        localStorage.set(selectedCountry.code, forKey: countryKey)
    }

    private func saveToiCloud() {
        if let data = try? JSONEncoder().encode(trackedApps) {
            iCloud.set(data, forKey: appsKey)
        }
        iCloud.set(selectedCountry.code, forKey: countryKey)
        iCloud.synchronize()
    }

    // MARK: - Force Sync
    func forceSync() {
        isSyncing = true
        iCloud.synchronize()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.syncFromiCloud()
        }
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
