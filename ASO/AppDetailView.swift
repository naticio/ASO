//
//  AppDetailView.swift
//  ASO
//

import SwiftUI
import Charts

struct AppDetailView: View {
    @Binding var app: TrackedApp
    @EnvironmentObject var dataStore: DataStore
    @State private var selectedTab = 0
    @State private var showingAddKeyword = false
    @State private var newKeyword = ""
    @State private var isRefreshing = false
    @State private var selectedKeywordCountry: Country = Country.all[0]
    @State private var topApps: [String: [AppStoreApp]] = [:]
    @State private var reviews: [AppReview] = []
    @State private var isLoadingReviews = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // App Header
                appHeader

                // Stats Overview
                statsOverview

                // Tab Selector
                Picker("View", selection: $selectedTab) {
                    Text("Keywords").tag(0)
                    Text("Rankings").tag(1)
                    Text("Reviews").tag(2)
                    Text("History").tag(3)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                // Tab Content
                switch selectedTab {
                case 0:
                    keywordsSection
                case 1:
                    rankingsSection
                case 2:
                    reviewsSection
                case 3:
                    historySection
                default:
                    EmptyView()
                }
            }
            .padding()
        }
        .navigationTitle(app.trackName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if isRefreshing {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Button(action: refreshRankings) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh Rankings")
                }
            }
        }
        .sheet(isPresented: $showingAddKeyword) {
            addKeywordSheet
        }
        .onAppear {
            selectedKeywordCountry = dataStore.selectedCountry
        }
    }

    // MARK: - App Header
    private var appHeader: some View {
        HStack(spacing: 16) {
            AsyncImage(url: URL(string: app.artworkUrl)) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } placeholder: {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.gray.opacity(0.3))
            }
            .frame(width: 80, height: 80)
            .cornerRadius(16)

            VStack(alignment: .leading, spacing: 4) {
                Text(app.trackName)
                    .font(.title2)
                    .fontWeight(.bold)
                    .lineLimit(2)

                Text(app.sellerName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    Text(app.primaryGenreName)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(6)

                    Text(app.bundleId)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding()
        .background(Color.secondarySystemBackground)
        .cornerRadius(16)
    }

    // MARK: - Stats Overview
    private var statsOverview: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 12) {
            StatBox(
                title: "Keywords",
                value: "\(app.keywords.count)",
                subtitle: "tracked",
                color: .blue
            )

            if let lastRating = app.ratingSnapshots.last {
                StatBox(
                    title: "Rating",
                    value: String(format: "%.1f", lastRating.rating),
                    subtitle: "\(formatNumber(lastRating.ratingCount)) reviews",
                    color: .yellow
                )
            } else {
                StatBox(
                    title: "Rating",
                    value: "N/A",
                    subtitle: "no data",
                    color: .gray
                )
            }

            StatBox(
                title: "Top 10",
                value: "\(keywordsInTop10)",
                subtitle: "keywords",
                color: .green
            )
        }
    }

    private var keywordsInTop10: Int {
        app.keywords.filter { ($0.currentRank ?? 999) <= 10 }.count
    }

    // MARK: - Keywords Section
    private var keywordsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Tracked Keywords")
                    .font(.headline)
                Spacer()
                Button(action: { showingAddKeyword = true }) {
                    Label("Add Keyword", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            if app.keywords.isEmpty {
                ContentUnavailableView {
                    Label("No Keywords", systemImage: "magnifyingglass")
                } description: {
                    Text("Add keywords to track your app's ranking in the App Store.")
                } actions: {
                    Button("Add Keyword") {
                        showingAddKeyword = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(height: 200)
            } else {
                // Keywords Table Header
                HStack(spacing: 0) {
                    Text("Keyword")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Country")
                        .frame(width: 80)
                    Text("Rank")
                        .frame(width: 60)
                    Text("Change")
                        .frame(width: 70)
                    Text("Pop.")
                        .frame(width: 50)
                    Text("Diff.")
                        .frame(width: 50)
                    Spacer()
                        .frame(width: 40)
                }
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.secondarySystemBackground)
                .cornerRadius(8)

                ForEach(app.keywords.sorted { ($0.currentRank ?? 999) < ($1.currentRank ?? 999) }) { keyword in
                    KeywordRowView(keyword: keyword, appId: app.id)
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Rankings Section
    private var rankingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Keyword Rankings")
                .font(.headline)
                .padding(.horizontal)

            if app.keywords.isEmpty {
                ContentUnavailableView("No Keywords", systemImage: "chart.line.uptrend.xyaxis", description: Text("Add keywords to see ranking trends."))
                    .frame(height: 300)
            } else {
                ForEach(app.keywords.prefix(5)) { keyword in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(keyword.keyword)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            if let country = Country.country(for: keyword.countryCode) {
                                Text(country.flag)
                            }
                            Spacer()
                            if let rank = keyword.currentRank {
                                Text("#\(rank)")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(rank <= 10 ? .green : .secondary)
                            }
                        }

                        if keyword.rankings.count > 1 {
                            Chart(keyword.rankings.sorted { $0.date < $1.date }) { ranking in
                                LineMark(
                                    x: .value("Date", ranking.date),
                                    y: .value("Rank", ranking.rank)
                                )
                                .foregroundStyle(Color.blue)

                                PointMark(
                                    x: .value("Date", ranking.date),
                                    y: .value("Rank", ranking.rank)
                                )
                                .foregroundStyle(Color.blue)
                            }
                            .chartYScale(domain: .automatic(includesZero: false))
                            .chartYAxis {
                                AxisMarks(position: .leading)
                            }
                            .frame(height: 100)
                        } else {
                            Text("Not enough data for chart")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(height: 50)
                        }
                    }
                    .padding()
                    .background(Color.secondarySystemBackground)
                    .cornerRadius(12)
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Reviews Section
    private var reviewsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Recent Reviews")
                    .font(.headline)
                Spacer()
                Button(action: loadReviews) {
                    if isLoadingReviews {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .padding(.horizontal)

            if reviews.isEmpty && !isLoadingReviews {
                ContentUnavailableView {
                    Label("No Reviews", systemImage: "star.bubble")
                } description: {
                    Text("Tap refresh to load recent reviews from the App Store.")
                } actions: {
                    Button("Load Reviews") {
                        loadReviews()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(height: 200)
            } else {
                ForEach(reviews.prefix(20)) { review in
                    ReviewCard(review: review)
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - History Section
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rating History")
                .font(.headline)
                .padding(.horizontal)

            if app.ratingSnapshots.count > 1 {
                Chart(app.ratingSnapshots.sorted { $0.date < $1.date }) { snapshot in
                    LineMark(
                        x: .value("Date", snapshot.date),
                        y: .value("Rating", snapshot.rating)
                    )
                    .foregroundStyle(Color.yellow)

                    PointMark(
                        x: .value("Date", snapshot.date),
                        y: .value("Rating", snapshot.rating)
                    )
                    .foregroundStyle(Color.yellow)
                }
                .chartYScale(domain: 1...5)
                .frame(height: 200)
                .padding()
                .background(Color.secondarySystemBackground)
                .cornerRadius(12)
                .padding(.horizontal)

                // Rating snapshots list
                ForEach(app.ratingSnapshots.sorted { $0.date > $1.date }.prefix(10)) { snapshot in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(snapshot.date, style: .date)
                                .font(.subheadline)
                            Text("\(snapshot.ratingCount) reviews")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .foregroundColor(.yellow)
                            Text(String(format: "%.1f", snapshot.rating))
                                .fontWeight(.bold)
                        }
                    }
                    .padding()
                    .background(Color.secondarySystemBackground)
                    .cornerRadius(8)
                }
                .padding(.horizontal)
            } else {
                ContentUnavailableView("Not Enough Data", systemImage: "chart.xyaxis.line", description: Text("Rating history will appear as data is collected over time."))
                    .frame(height: 200)
            }
        }
    }

    // MARK: - Add Keyword Sheet
    private var addKeywordSheet: some View {
        NavigationStack {
            Form {
                Section("Keyword") {
                    TextField("Enter keyword", text: $newKeyword)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                }

                Section("Country") {
                    Picker("Country", selection: $selectedKeywordCountry) {
                        ForEach(Country.all) { country in
                            Text("\(country.flag) \(country.name)")
                                .tag(country)
                        }
                    }
                }
            }
            .navigationTitle("Add Keyword")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        newKeyword = ""
                        showingAddKeyword = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addKeyword()
                    }
                    .disabled(newKeyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(width: 400, height: 250)
        #endif
    }

    // MARK: - Actions
    private func addKeyword() {
        let keyword = newKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return }

        dataStore.addKeyword(keyword, to: app.id, countryCode: selectedKeywordCountry.code)
        newKeyword = ""
        showingAddKeyword = false

        // Immediately check ranking for new keyword
        Task {
            if let appIndex = dataStore.trackedApps.firstIndex(where: { $0.id == app.id }),
               let keywordIndex = dataStore.trackedApps[appIndex].keywords.firstIndex(where: {
                   $0.keyword.lowercased() == keyword.lowercased() && $0.countryCode == selectedKeywordCountry.code
               }) {
                if let rank = try? await AppStoreService.shared.searchKeywordRanking(
                    keyword: keyword,
                    appId: app.trackId,
                    country: selectedKeywordCountry.code
                ) {
                    dataStore.updateKeywordRanking(
                        dataStore.trackedApps[appIndex].keywords[keywordIndex].id,
                        for: app.id,
                        rank: rank
                    )
                }
            }
        }
    }

    private func refreshRankings() {
        isRefreshing = true

        Task {
            for keyword in app.keywords {
                if let rank = try? await AppStoreService.shared.searchKeywordRanking(
                    keyword: keyword.keyword,
                    appId: app.trackId,
                    country: keyword.countryCode
                ) {
                    dataStore.updateKeywordRanking(keyword.id, for: app.id, rank: rank)
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }

            // Update rating
            if let updatedApp = try? await AppStoreService.shared.lookupApp(
                id: app.trackId,
                country: dataStore.selectedCountry.code
            ) {
                if let rating = updatedApp.averageUserRating, let count = updatedApp.userRatingCount {
                    dataStore.addRatingSnapshot(to: app.id, rating: rating, ratingCount: count)
                }
            }

            isRefreshing = false
        }
    }

    private func loadReviews() {
        isLoadingReviews = true

        Task {
            do {
                reviews = try await AppStoreService.shared.fetchReviews(
                    appId: app.trackId,
                    country: dataStore.selectedCountry.code
                )
            } catch {
                print("Failed to load reviews: \(error)")
            }
            isLoadingReviews = false
        }
    }

    private func formatNumber(_ number: Int) -> String {
        if number >= 1_000_000 {
            return String(format: "%.1fM", Double(number) / 1_000_000)
        } else if number >= 1_000 {
            return String(format: "%.1fK", Double(number) / 1_000)
        }
        return "\(number)"
    }
}

// MARK: - Stat Box
struct StatBox: View {
    let title: String
    let value: String
    let subtitle: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.secondarySystemBackground)
        .cornerRadius(12)
    }
}

// MARK: - Keyword Row View
struct KeywordRowView: View {
    let keyword: TrackedKeyword
    let appId: UUID
    @EnvironmentObject var dataStore: DataStore

    var body: some View {
        HStack(spacing: 0) {
            Text(keyword.keyword)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let country = Country.country(for: keyword.countryCode) {
                Text(country.flag)
                    .frame(width: 80)
            }

            if let rank = keyword.currentRank {
                Text("#\(rank)")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(rankColor(rank))
                    .frame(width: 60)
            } else {
                Text("-")
                    .foregroundColor(.secondary)
                    .frame(width: 60)
            }

            rankChangeView
                .frame(width: 70)

            Text("\(keyword.popularity)")
                .font(.caption)
                .foregroundColor(.blue)
                .frame(width: 50)

            Text("\(keyword.difficulty)")
                .font(.caption)
                .foregroundColor(.orange)
                .frame(width: 50)

            Button(action: {
                dataStore.removeKeyword(keyword.id, from: appId)
            }) {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .frame(width: 40)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color.secondarySystemBackground)
        .cornerRadius(8)
    }

    @ViewBuilder
    private var rankChangeView: some View {
        if let change = keyword.rankChange {
            HStack(spacing: 2) {
                Image(systemName: change > 0 ? "arrow.up" : (change < 0 ? "arrow.down" : "minus"))
                    .font(.caption2)
                Text("\(abs(change))")
                    .font(.caption)
            }
            .foregroundColor(change > 0 ? .green : (change < 0 ? .red : .secondary))
        } else {
            Text("-")
                .foregroundColor(.secondary)
        }
    }

    private func rankColor(_ rank: Int) -> Color {
        if rank <= 3 { return .green }
        if rank <= 10 { return .blue }
        if rank <= 50 { return .orange }
        return .secondary
    }
}

// MARK: - Review Card
struct ReviewCard: View {
    let review: AppReview

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 2) {
                    ForEach(0..<5) { index in
                        Image(systemName: index < review.rating ? "star.fill" : "star")
                            .font(.caption)
                            .foregroundColor(.yellow)
                    }
                }

                Spacer()

                if let country = Country.country(for: review.countryCode) {
                    Text(country.flag)
                }

                if let version = review.version {
                    Text("v\(version)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Text(review.title)
                .font(.subheadline)
                .fontWeight(.semibold)

            Text(review.content)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(4)

            HStack {
                Text(review.author)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Text(review.date, style: .relative)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color.secondarySystemBackground)
        .cornerRadius(12)
    }
}
