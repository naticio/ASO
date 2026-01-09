//
//  KeywordsOverviewView.swift
//  ASO
//

import SwiftUI

struct KeywordsOverviewView: View {
    @EnvironmentObject var dataStore: DataStore
    @Binding var selectedApp: TrackedApp?
    @State private var searchText = ""
    @State private var sortOrder: KeywordSortOrder = .rank
    @State private var isRefreshing = false

    enum KeywordSortOrder: String, CaseIterable {
        case rank = "Rank"
        case keyword = "Keyword"
        case app = "App"
        case country = "Country"
    }

    var allKeywords: [(app: TrackedApp, keyword: TrackedKeyword)] {
        var result: [(TrackedApp, TrackedKeyword)] = []
        for app in dataStore.trackedApps {
            for keyword in app.keywords {
                result.append((app, keyword))
            }
        }
        return result
    }

    var filteredKeywords: [(app: TrackedApp, keyword: TrackedKeyword)] {
        var keywords = allKeywords

        if !searchText.isEmpty {
            keywords = keywords.filter {
                $0.keyword.keyword.localizedCaseInsensitiveContains(searchText) ||
                $0.app.trackName.localizedCaseInsensitiveContains(searchText)
            }
        }

        switch sortOrder {
        case .rank:
            keywords.sort { ($0.keyword.currentRank ?? 999) < ($1.keyword.currentRank ?? 999) }
        case .keyword:
            keywords.sort { $0.keyword.keyword < $1.keyword.keyword }
        case .app:
            keywords.sort { $0.app.trackName < $1.app.trackName }
        case .country:
            keywords.sort { $0.keyword.countryCode < $1.keyword.countryCode }
        }

        return keywords
    }

    var body: some View {
        Group {
            if allKeywords.isEmpty {
                emptyState
            } else {
                keywordsList
            }
        }
        .navigationTitle("Keywords")
        .searchable(text: $searchText, prompt: "Search keywords")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ForEach(KeywordSortOrder.allCases, id: \.self) { order in
                        Button(action: { sortOrder = order }) {
                            HStack {
                                Text(order.rawValue)
                                if sortOrder == order {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
            }

            ToolbarItem(placement: .primaryAction) {
                if isRefreshing {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Button(action: refreshAllRankings) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Keywords", systemImage: "magnifyingglass")
        } description: {
            Text("Add keywords to your tracked apps to see them here.")
        }
    }

    private var keywordsList: some View {
        List {
            // Summary Section
            Section {
                HStack {
                    VStack(alignment: .leading) {
                        Text("\(allKeywords.count)")
                            .font(.title)
                            .fontWeight(.bold)
                        Text("Total Keywords")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .leading) {
                        Text("\(keywordsInTop10)")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                        Text("Top 10")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .leading) {
                        Text("\(keywordsImproved)")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.blue)
                        Text("Improved")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }

            // Keywords
            Section("All Keywords") {
                ForEach(filteredKeywords, id: \.keyword.id) { item in
                    KeywordOverviewRow(app: item.app, keyword: item.keyword)
                        .onTapGesture {
                            selectedApp = item.app
                        }
                }
            }
        }
        .listStyle(.inset)
    }

    private var keywordsInTop10: Int {
        allKeywords.filter { ($0.keyword.currentRank ?? 999) <= 10 }.count
    }

    private var keywordsImproved: Int {
        allKeywords.filter { ($0.keyword.rankChange ?? 0) > 0 }.count
    }

    private func refreshAllRankings() {
        isRefreshing = true
        Task {
            await dataStore.refreshAllRankings()
            isRefreshing = false
        }
    }
}

// MARK: - Keyword Overview Row
struct KeywordOverviewRow: View {
    let app: TrackedApp
    let keyword: TrackedKeyword

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: app.artworkUrl)) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } placeholder: {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.3))
            }
            .frame(width: 36, height: 36)
            .cornerRadius(8)

            VStack(alignment: .leading, spacing: 2) {
                Text(keyword.keyword)
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack(spacing: 8) {
                    Text(app.trackName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    if let country = Country.country(for: keyword.countryCode) {
                        Text(country.flag)
                            .font(.caption)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if let rank = keyword.currentRank {
                    Text("#\(rank)")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(rankColor(rank))
                } else {
                    Text("-")
                        .foregroundColor(.secondary)
                }

                if let change = keyword.rankChange {
                    HStack(spacing: 2) {
                        Image(systemName: change > 0 ? "arrow.up" : (change < 0 ? "arrow.down" : "minus"))
                            .font(.caption2)
                        Text("\(abs(change))")
                            .font(.caption)
                    }
                    .foregroundColor(change > 0 ? .green : (change < 0 ? .red : .secondary))
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func rankColor(_ rank: Int) -> Color {
        if rank <= 3 { return .green }
        if rank <= 10 { return .blue }
        if rank <= 50 { return .orange }
        return .secondary
    }
}

#Preview {
    KeywordsOverviewView(selectedApp: .constant(nil))
        .environmentObject(DataStore.shared)
}
