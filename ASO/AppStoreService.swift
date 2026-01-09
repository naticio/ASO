//
//  AppStoreService.swift
//  ASO
//

import Foundation

actor AppStoreService {
    static let shared = AppStoreService()

    private let baseURL = "https://itunes.apple.com"
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    // MARK: - Search Apps
    func searchApps(query: String, country: String = "us", limit: Int = 50) async throws -> [AppStoreApp] {
        guard !query.isEmpty else { return [] }

        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlString = "\(baseURL)/search?term=\(encodedQuery)&country=\(country)&media=software&entity=software&limit=\(limit)"

        guard let url = URL(string: urlString) else {
            throw AppStoreError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppStoreError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw AppStoreError.httpError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        let searchResponse = try decoder.decode(AppStoreSearchResponse.self, from: data)
        return searchResponse.results
    }

    // MARK: - Lookup App by ID
    func lookupApp(id: Int, country: String = "us") async throws -> AppStoreApp? {
        let urlString = "\(baseURL)/lookup?id=\(id)&country=\(country)"

        guard let url = URL(string: urlString) else {
            throw AppStoreError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppStoreError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw AppStoreError.httpError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        let searchResponse = try decoder.decode(AppStoreSearchResponse.self, from: data)
        return searchResponse.results.first
    }

    // MARK: - Lookup App by Bundle ID
    func lookupApp(bundleId: String, country: String = "us") async throws -> AppStoreApp? {
        let urlString = "\(baseURL)/lookup?bundleId=\(bundleId)&country=\(country)"

        guard let url = URL(string: urlString) else {
            throw AppStoreError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppStoreError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw AppStoreError.httpError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        let searchResponse = try decoder.decode(AppStoreSearchResponse.self, from: data)
        return searchResponse.results.first
    }

    // MARK: - Search Keyword Rankings
    func searchKeywordRanking(keyword: String, appId: Int, country: String = "us") async throws -> Int? {
        let results = try await searchApps(query: keyword, country: country, limit: 200)

        for (index, app) in results.enumerated() {
            if app.trackId == appId {
                return index + 1
            }
        }

        return nil
    }

    // MARK: - Get Top Apps for Keyword
    func getTopAppsForKeyword(keyword: String, country: String = "us", limit: Int = 10) async throws -> [AppStoreApp] {
        let results = try await searchApps(query: keyword, country: country, limit: limit)
        return results
    }

    // MARK: - Fetch Reviews (RSS Feed)
    func fetchReviews(appId: Int, country: String = "us", page: Int = 1) async throws -> [AppReview] {
        let urlString = "https://itunes.apple.com/\(country)/rss/customerreviews/page=\(page)/id=\(appId)/sortby=mostrecent/json"

        guard let url = URL(string: urlString) else {
            throw AppStoreError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppStoreError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw AppStoreError.httpError(httpResponse.statusCode)
        }

        return parseReviewsFromRSS(data: data, countryCode: country)
    }

    // MARK: - Parse Reviews from RSS JSON
    private func parseReviewsFromRSS(data: Data, countryCode: String) -> [AppReview] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let feed = json["feed"] as? [String: Any],
              let entries = feed["entry"] as? [[String: Any]] else {
            return []
        }

        var reviews: [AppReview] = []

        for entry in entries {
            guard let author = (entry["author"] as? [String: Any])?["name"] as? [String: Any],
                  let authorName = author["label"] as? String,
                  let ratingDict = entry["im:rating"] as? [String: Any],
                  let ratingString = ratingDict["label"] as? String,
                  let rating = Int(ratingString),
                  let titleDict = entry["title"] as? [String: Any],
                  let title = titleDict["label"] as? String,
                  let contentDict = entry["content"] as? [String: Any],
                  let content = contentDict["label"] as? String,
                  let idDict = entry["id"] as? [String: Any],
                  let id = idDict["label"] as? String else {
                continue
            }

            let versionDict = entry["im:version"] as? [String: Any]
            let version = versionDict?["label"] as? String

            let review = AppReview(
                id: id,
                author: authorName,
                rating: rating,
                title: title,
                content: content,
                date: Date(),
                countryCode: countryCode,
                version: version
            )

            reviews.append(review)
        }

        return reviews
    }
}

// MARK: - Errors
enum AppStoreError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case decodingError
    case noResults

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .decodingError:
            return "Failed to decode response"
        case .noResults:
            return "No results found"
        }
    }
}
