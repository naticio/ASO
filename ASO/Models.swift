//
//  Models.swift
//  ASO
//

import Foundation
import SwiftUI

// MARK: - App Store Search Response
struct AppStoreSearchResponse: Codable {
    let resultCount: Int
    let results: [AppStoreApp]
}

// MARK: - App Store App
struct AppStoreApp: Codable, Identifiable, Hashable {
    let trackId: Int
    let trackName: String
    let bundleId: String
    let sellerName: String
    let primaryGenreName: String
    let genres: [String]?
    let artworkUrl100: String
    let artworkUrl512: String?
    let screenshotUrls: [String]?
    let description: String?
    let releaseNotes: String?
    let version: String?
    let averageUserRating: Double?
    let userRatingCount: Int?
    let price: Double?
    let formattedPrice: String?
    let trackViewUrl: String?
    let currentVersionReleaseDate: String?
    let releaseDate: String?
    let minimumOsVersion: String?
    let fileSizeBytes: String?
    let contentAdvisoryRating: String?

    var id: Int { trackId }

    var artworkUrl: String {
        artworkUrl512 ?? artworkUrl100
    }

    var ratingStars: String {
        guard let rating = averageUserRating else { return "N/A" }
        let fullStars = Int(rating)
        let hasHalfStar = rating - Double(fullStars) >= 0.5
        var stars = String(repeating: "★", count: fullStars)
        if hasHalfStar && fullStars < 5 {
            stars += "½"
        }
        stars += String(repeating: "☆", count: 5 - fullStars - (hasHalfStar ? 1 : 0))
        return stars
    }

    var formattedRatingCount: String {
        guard let count = userRatingCount else { return "0" }
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(trackId)
    }

    static func == (lhs: AppStoreApp, rhs: AppStoreApp) -> Bool {
        lhs.trackId == rhs.trackId
    }
}

// MARK: - Tracked App (Local Storage)
struct TrackedApp: Codable, Identifiable, Hashable {
    let id: UUID
    let trackId: Int
    let trackName: String
    let bundleId: String
    let sellerName: String
    let artworkUrl: String
    let primaryGenreName: String
    var keywords: [TrackedKeyword]
    var ratingSnapshots: [RatingSnapshot]
    var dateAdded: Date
    var lastUpdated: Date

    init(from app: AppStoreApp) {
        self.id = UUID()
        self.trackId = app.trackId
        self.trackName = app.trackName
        self.bundleId = app.bundleId
        self.sellerName = app.sellerName
        self.artworkUrl = app.artworkUrl
        self.primaryGenreName = app.primaryGenreName
        self.keywords = []
        self.ratingSnapshots = []
        self.dateAdded = Date()
        self.lastUpdated = Date()
    }
}

// MARK: - Tracked Keyword
struct TrackedKeyword: Codable, Identifiable, Hashable {
    let id: UUID
    let keyword: String
    let countryCode: String
    var rankings: [KeywordRanking]
    var dateAdded: Date

    init(keyword: String, countryCode: String) {
        self.id = UUID()
        self.keyword = keyword
        self.countryCode = countryCode
        self.rankings = []
        self.dateAdded = Date()
    }

    var currentRank: Int? {
        rankings.sorted { $0.date > $1.date }.first?.rank
    }

    var previousRank: Int? {
        let sorted = rankings.sorted { $0.date > $1.date }
        guard sorted.count > 1 else { return nil }
        return sorted[1].rank
    }

    var rankChange: Int? {
        guard let current = currentRank, let previous = previousRank else { return nil }
        return previous - current
    }

    var popularity: Int {
        Int.random(in: 20...80)
    }

    var difficulty: Int {
        Int.random(in: 10...90)
    }
}

// MARK: - Keyword Ranking
struct KeywordRanking: Codable, Identifiable, Hashable {
    let id: UUID
    let rank: Int
    let date: Date
    let impressions: Int?

    init(rank: Int, date: Date = Date(), impressions: Int? = nil) {
        self.id = UUID()
        self.rank = rank
        self.date = date
        self.impressions = impressions
    }
}

// MARK: - Rating Snapshot
struct RatingSnapshot: Codable, Identifiable, Hashable {
    let id: UUID
    let rating: Double
    let ratingCount: Int
    let date: Date

    init(rating: Double, ratingCount: Int, date: Date = Date()) {
        self.id = UUID()
        self.rating = rating
        self.ratingCount = ratingCount
        self.date = date
    }
}

// MARK: - App Review
struct AppReview: Codable, Identifiable, Hashable {
    let id: String
    let author: String
    let rating: Int
    let title: String
    let content: String
    let date: Date
    let countryCode: String
    let version: String?
}

// MARK: - Country
struct Country: Identifiable, Hashable {
    let code: String
    let name: String
    let flag: String

    var id: String { code }

    static let all: [Country] = [
        Country(code: "us", name: "United States", flag: "🇺🇸"),
        Country(code: "gb", name: "United Kingdom", flag: "🇬🇧"),
        Country(code: "ca", name: "Canada", flag: "🇨🇦"),
        Country(code: "au", name: "Australia", flag: "🇦🇺"),
        Country(code: "de", name: "Germany", flag: "🇩🇪"),
        Country(code: "fr", name: "France", flag: "🇫🇷"),
        Country(code: "es", name: "Spain", flag: "🇪🇸"),
        Country(code: "it", name: "Italy", flag: "🇮🇹"),
        Country(code: "jp", name: "Japan", flag: "🇯🇵"),
        Country(code: "kr", name: "South Korea", flag: "🇰🇷"),
        Country(code: "cn", name: "China", flag: "🇨🇳"),
        Country(code: "tw", name: "Taiwan", flag: "🇹🇼"),
        Country(code: "hk", name: "Hong Kong", flag: "🇭🇰"),
        Country(code: "sg", name: "Singapore", flag: "🇸🇬"),
        Country(code: "in", name: "India", flag: "🇮🇳"),
        Country(code: "br", name: "Brazil", flag: "🇧🇷"),
        Country(code: "mx", name: "Mexico", flag: "🇲🇽"),
        Country(code: "ar", name: "Argentina", flag: "🇦🇷"),
        Country(code: "cl", name: "Chile", flag: "🇨🇱"),
        Country(code: "co", name: "Colombia", flag: "🇨🇴"),
        Country(code: "nl", name: "Netherlands", flag: "🇳🇱"),
        Country(code: "be", name: "Belgium", flag: "🇧🇪"),
        Country(code: "se", name: "Sweden", flag: "🇸🇪"),
        Country(code: "no", name: "Norway", flag: "🇳🇴"),
        Country(code: "dk", name: "Denmark", flag: "🇩🇰"),
        Country(code: "fi", name: "Finland", flag: "🇫🇮"),
        Country(code: "pl", name: "Poland", flag: "🇵🇱"),
        Country(code: "cz", name: "Czech Republic", flag: "🇨🇿"),
        Country(code: "at", name: "Austria", flag: "🇦🇹"),
        Country(code: "ch", name: "Switzerland", flag: "🇨🇭"),
        Country(code: "pt", name: "Portugal", flag: "🇵🇹"),
        Country(code: "ru", name: "Russia", flag: "🇷🇺"),
        Country(code: "tr", name: "Turkey", flag: "🇹🇷"),
        Country(code: "ae", name: "UAE", flag: "🇦🇪"),
        Country(code: "sa", name: "Saudi Arabia", flag: "🇸🇦"),
        Country(code: "il", name: "Israel", flag: "🇮🇱"),
        Country(code: "za", name: "South Africa", flag: "🇿🇦"),
        Country(code: "nz", name: "New Zealand", flag: "🇳🇿"),
        Country(code: "ph", name: "Philippines", flag: "🇵🇭"),
        Country(code: "th", name: "Thailand", flag: "🇹🇭"),
        Country(code: "my", name: "Malaysia", flag: "🇲🇾"),
        Country(code: "id", name: "Indonesia", flag: "🇮🇩"),
        Country(code: "vn", name: "Vietnam", flag: "🇻🇳"),
        Country(code: "ie", name: "Ireland", flag: "🇮🇪"),
        Country(code: "gr", name: "Greece", flag: "🇬🇷"),
        Country(code: "hu", name: "Hungary", flag: "🇭🇺"),
        Country(code: "ro", name: "Romania", flag: "🇷🇴"),
        Country(code: "bg", name: "Bulgaria", flag: "🇧🇬"),
        Country(code: "sk", name: "Slovakia", flag: "🇸🇰"),
        Country(code: "hr", name: "Croatia", flag: "🇭🇷"),
        Country(code: "si", name: "Slovenia", flag: "🇸🇮"),
        Country(code: "ua", name: "Ukraine", flag: "🇺🇦"),
        Country(code: "eg", name: "Egypt", flag: "🇪🇬"),
        Country(code: "ng", name: "Nigeria", flag: "🇳🇬"),
        Country(code: "ke", name: "Kenya", flag: "🇰🇪"),
        Country(code: "pe", name: "Peru", flag: "🇵🇪"),
        Country(code: "ve", name: "Venezuela", flag: "🇻🇪"),
        Country(code: "ec", name: "Ecuador", flag: "🇪🇨"),
        Country(code: "pk", name: "Pakistan", flag: "🇵🇰"),
        Country(code: "bd", name: "Bangladesh", flag: "🇧🇩")
    ]

    static func country(for code: String) -> Country? {
        all.first { $0.code == code }
    }
}

// MARK: - Navigation
enum NavigationItem: Hashable {
    case dashboard
    case apps
    case keywords
    case reviews
    case settings
}
