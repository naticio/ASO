//
//  MainView.swift
//  ASO
//

import SwiftUI

struct MainView: View {
    @StateObject private var dataStore = DataStore.shared
    @State private var selectedApp: TrackedApp?
    @State private var showingAddApp = false
    @State private var showingAddKeyword = false
    @State private var showingSettings = false

    var body: some View {
        NavigationSplitView {
            // Left sidebar - Apps list
            AppsSidebar(selectedApp: $selectedApp, showingAddApp: $showingAddApp)
                .environmentObject(dataStore)
        } detail: {
            // Main content - Keywords table
            if let app = selectedApp {
                KeywordTableView(app: binding(for: app), showingAddKeyword: $showingAddKeyword)
                    .environmentObject(dataStore)
            } else {
                ContentUnavailableView("Select an App", systemImage: "apps.iphone", description: Text("Choose an app from the sidebar to view keywords"))
            }
        }
        .environmentObject(dataStore)
        .sheet(isPresented: $showingAddApp) {
            AppSearchSheet()
                .environmentObject(dataStore)
        }
        .sheet(isPresented: $showingAddKeyword) {
            if let app = selectedApp {
                AddKeywordSheet(app: binding(for: app))
                    .environmentObject(dataStore)
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(dataStore)
        }
    }

    private func binding(for app: TrackedApp) -> Binding<TrackedApp> {
        Binding(
            get: {
                dataStore.trackedApps.first { $0.id == app.id } ?? app
            },
            set: { newValue in
                if let index = dataStore.trackedApps.firstIndex(where: { $0.id == app.id }) {
                    dataStore.trackedApps[index] = newValue
                }
            }
        )
    }
}

// MARK: - Apps Sidebar
struct AppsSidebar: View {
    @EnvironmentObject var dataStore: DataStore
    @Binding var selectedApp: TrackedApp?
    @Binding var showingAddApp: Bool

    var body: some View {
        List(selection: $selectedApp) {
            ForEach(dataStore.trackedApps) { app in
                AppSidebarRow(app: app)
                    .tag(app)
                    .contextMenu {
                        Button(role: .destructive) {
                            if selectedApp?.id == app.id {
                                selectedApp = nil
                            }
                            dataStore.removeApp(app)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Apps")
        #if os(macOS)
        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingAddApp = true }) {
                    Image(systemName: "plus")
                }
                .help("Add App")
            }
        }
        .overlay {
            if dataStore.trackedApps.isEmpty {
                ContentUnavailableView {
                    Label("No Apps", systemImage: "apps.iphone")
                } description: {
                    Text("Add your first app")
                } actions: {
                    Button("Add App") {
                        showingAddApp = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}

// MARK: - App Sidebar Row
struct AppSidebarRow: View {
    let app: TrackedApp

    var body: some View {
        HStack(spacing: 10) {
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
                Text(app.trackName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Image(systemName: "iphone")
                        .font(.system(size: 9))
                    Text("iPhone")
                        .font(.system(size: 10))
                }
                .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Keyword Table View
struct KeywordTableView: View {
    @Binding var app: TrackedApp
    @Binding var showingAddKeyword: Bool
    @EnvironmentObject var dataStore: DataStore
    @State private var sortOrder: KeywordSortOrder = .position
    @State private var sortAscending = true
    @State private var isRefreshing = false
    @State private var competitorApps: [UUID: [AppStoreApp]] = [:]
    @State private var searchText = ""
    @State private var isSearching = false

    enum KeywordSortOrder {
        case keyword, popularity, difficulty, position, downloads
    }

    var filteredKeywords: [TrackedKeyword] {
        if searchText.isEmpty {
            return app.keywords
        }
        return app.keywords.filter { $0.keyword.localizedCaseInsensitiveContains(searchText) }
    }

    var sortedKeywords: [TrackedKeyword] {
        let keywords = filteredKeywords
        return keywords.sorted { a, b in
            let result: Bool
            switch sortOrder {
            case .keyword:
                result = a.keyword < b.keyword
            case .popularity:
                result = a.popularity < b.popularity
            case .difficulty:
                result = a.difficulty < b.difficulty
            case .position:
                let rankA = a.currentRank ?? 999
                let rankB = b.currentRank ?? 999
                result = rankA < rankB
            case .downloads:
                result = a.estimatedDownloads < b.estimatedDownloads
            }
            return sortAscending ? result : !result
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            tableToolbar

            Divider()

            // Table Header
            tableHeader

            Divider()

            // Table Content
            if app.keywords.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(sortedKeywords) { keyword in
                            KeywordRow(
                                keyword: keyword,
                                appId: app.id,
                                competitors: competitorApps[keyword.id] ?? []
                            )
                            Divider()
                        }
                    }
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .onAppear {
            loadCompetitors()
        }
    }

    // MARK: - Toolbar
    private var tableToolbar: some View {
        HStack(spacing: 12) {
            // Refresh button
            Button(action: refreshRankings) {
                if isRefreshing {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.plain)
            .disabled(isRefreshing)

            // Sort picker
            Picker("Sort", selection: $sortOrder) {
                Text("Keywords").tag(KeywordSortOrder.keyword)
                Text("Popularity").tag(KeywordSortOrder.popularity)
                Text("Difficulty").tag(KeywordSortOrder.difficulty)
                Text("Position").tag(KeywordSortOrder.position)
            }
            .pickerStyle(.menu)
            .frame(width: 120)

            // Country selector
            HStack(spacing: 4) {
                Text(dataStore.selectedCountry.flag)
                Text(dataStore.selectedCountry.code.uppercased())
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.2))
            .cornerRadius(6)

            Spacer()

            // Add Keywords button
            Button(action: { showingAddKeyword = true }) {
                HStack(spacing: 4) {
                    Text("Add Keywords")
                    Image(systemName: "plus")
                }
            }
            .buttonStyle(.borderedProminent)

            // Keywords count
            Text("\(app.keywords.count) keywords")
                .font(.caption)
                .foregroundColor(.secondary)

            // Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))

                if isSearching {
                    TextField("Search keywords", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .frame(width: 150)

                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                    }

                    Button(action: {
                        isSearching = false
                        searchText = ""
                    }) {
                        Text("Done")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(isSearching ? Color.secondary.opacity(0.15) : Color.clear)
            .cornerRadius(6)
            .onTapGesture {
                if !isSearching {
                    isSearching = true
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Table Header
    private var tableHeader: some View {
        HStack(spacing: 0) {
            headerButton("Keyword", width: nil, alignment: .leading, sort: .keyword)

            headerButton("Popularity", width: 100, alignment: .leading, sort: .popularity)
                .help("Search popularity score (0-100)")

            headerButton("Difficulty", width: 100, alignment: .leading, sort: .difficulty)
                .help("Competition difficulty score (0-100)")

            headerButton("Downloads", width: 80, alignment: .trailing, sort: .downloads)
                .help("Estimated monthly downloads from this keyword")

            headerButton("Position", width: 100, alignment: .trailing, sort: .position)

            Text("Apps in Ranking")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 180, alignment: .leading)
                .padding(.horizontal, 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.05))
    }

    private func headerButton(_ title: String, width: CGFloat?, alignment: Alignment, sort: KeywordSortOrder) -> some View {
        Button(action: {
            if sortOrder == sort {
                sortAscending.toggle()
            } else {
                sortOrder = sort
                sortAscending = true
            }
        }) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                if sortOrder == sort {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9))
                }
            }
            .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .frame(width: width, alignment: alignment)
        .frame(maxWidth: width == nil ? .infinity : nil, alignment: alignment)
        .padding(.horizontal, 8)
    }

    // MARK: - Empty State
    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Keywords", systemImage: "magnifyingglass")
        } description: {
            Text("Add keywords to track your app's ranking")
        } actions: {
            Button("Add Keyword") {
                showingAddKeyword = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions
    private func refreshRankings() {
        isRefreshing = true
        Task {
            for index in app.keywords.indices {
                let keyword = app.keywords[index]
                if let rank = try? await AppStoreService.shared.searchKeywordRanking(
                    keyword: keyword.keyword,
                    appId: app.trackId,
                    country: keyword.countryCode
                ) {
                    dataStore.updateKeywordRanking(keyword.id, for: app.id, rank: rank)
                }

                // Load competitors
                if let competitors = try? await AppStoreService.shared.getTopAppsForKeyword(
                    keyword: keyword.keyword,
                    country: keyword.countryCode,
                    limit: 5
                ) {
                    competitorApps[keyword.id] = competitors
                }

                try? await Task.sleep(nanoseconds: 300_000_000)
            }
            isRefreshing = false
        }
    }

    private func loadCompetitors() {
        Task {
            for keyword in app.keywords {
                if let competitors = try? await AppStoreService.shared.getTopAppsForKeyword(
                    keyword: keyword.keyword,
                    country: keyword.countryCode,
                    limit: 5
                ) {
                    competitorApps[keyword.id] = competitors
                }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
    }
}

// MARK: - Keyword Row
struct KeywordRow: View {
    let keyword: TrackedKeyword
    let appId: UUID
    let competitors: [AppStoreApp]
    @EnvironmentObject var dataStore: DataStore
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 0) {
            // Keyword
            Text(keyword.keyword)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)

            // Popularity bar
            PopularityBar(value: keyword.popularity, color: .yellow)
                .frame(width: 100)
                .padding(.horizontal, 8)

            // Difficulty bar
            DifficultyBar(value: keyword.difficulty)
                .frame(width: 100)
                .padding(.horizontal, 8)

            // Downloads
            DownloadsCell(downloads: keyword.estimatedDownloads)
                .frame(width: 80, alignment: .trailing)
                .padding(.horizontal, 8)

            // Position
            PositionCell(rank: keyword.currentRank, change: keyword.rankChange)
                .frame(width: 100, alignment: .trailing)
                .padding(.horizontal, 8)

            // Competitors
            CompetitorsCell(apps: competitors)
                .frame(width: 180, alignment: .leading)
                .padding(.horizontal, 8)

            // Delete button (on hover)
            Button(action: {
                dataStore.removeKeyword(keyword.id, from: appId)
            }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
                    .opacity(isHovering ? 1 : 0)
            }
            .buttonStyle(.plain)
            .frame(width: 24)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isHovering ? Color.secondary.opacity(0.1) : Color.clear)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Downloads Cell
struct DownloadsCell: View {
    let downloads: Int

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 10))
                .foregroundColor(.blue)
            Text(formattedDownloads)
                .font(.system(size: 12, weight: .medium))
        }
    }

    var formattedDownloads: String {
        if downloads >= 1_000_000 {
            return String(format: "%.1fM", Double(downloads) / 1_000_000.0)
        } else if downloads >= 1000 {
            return String(format: "%.1fK", Double(downloads) / 1000.0)
        }
        return "\(downloads)"
    }
}

// MARK: - Popularity Bar
struct PopularityBar: View {
    let value: Int
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Text("\(value)")
                .font(.system(size: 12, weight: .medium))
                .frame(width: 28, alignment: .trailing)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.2))

                    RoundedRectangle(cornerRadius: 3)
                        .fill(
                            LinearGradient(
                                colors: [.yellow, .orange],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * CGFloat(value) / 100)
                }
            }
            .frame(height: 8)
        }
    }
}

// MARK: - Difficulty Bar
struct DifficultyBar: View {
    let value: Int

    var barColor: LinearGradient {
        if value < 30 {
            return LinearGradient(colors: [.green, .green], startPoint: .leading, endPoint: .trailing)
        } else if value < 60 {
            return LinearGradient(colors: [.yellow, .orange], startPoint: .leading, endPoint: .trailing)
        } else {
            return LinearGradient(colors: [.orange, .red], startPoint: .leading, endPoint: .trailing)
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("\(value)")
                .font(.system(size: 12, weight: .medium))
                .frame(width: 28, alignment: .trailing)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.2))

                    RoundedRectangle(cornerRadius: 3)
                        .fill(barColor)
                        .frame(width: geometry.size.width * CGFloat(value) / 100)
                }
            }
            .frame(height: 8)
        }
    }
}

// MARK: - Position Cell
struct PositionCell: View {
    let rank: Int?
    let change: Int?

    var body: some View {
        HStack(spacing: 6) {
            if let rank = rank {
                // Trophy for top 3
                if rank <= 3 {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 10))
                        .foregroundColor(rank == 1 ? .yellow : (rank == 2 ? .gray : .orange))
                }

                Text("#")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Text("\(rank)")
                    .font(.system(size: 13, weight: .semibold))

                // Change indicator
                if let change = change, change != 0 {
                    HStack(spacing: 1) {
                        Image(systemName: change > 0 ? "arrow.up" : "arrow.down")
                            .font(.system(size: 9))
                        Text("\(abs(change))")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(change > 0 ? .green : .red)
                }
            } else {
                Text("...")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Competitors Cell
struct CompetitorsCell: View {
    let apps: [AppStoreApp]

    var body: some View {
        HStack(spacing: -6) {
            ForEach(apps.prefix(5)) { app in
                AsyncImage(url: URL(string: app.artworkUrl100)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } placeholder: {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                }
                .frame(width: 24, height: 24)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .controlBackgroundColor), lineWidth: 2)
                )
                .help(app.trackName)
            }

            if apps.isEmpty {
                Text("...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Add Keyword Sheet
struct AddKeywordSheet: View {
    @Binding var app: TrackedApp
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) var dismiss
    @State private var keywords = ""
    @State private var selectedCountry: Country = Country.all[0]

    var body: some View {
        NavigationStack {
            Form {
                Section("Keywords") {
                    TextEditor(text: $keywords)
                        .frame(minHeight: 100)
                        .font(.system(size: 13, design: .monospaced))
                }

                Section {
                    Text("Enter one keyword per line")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("Country") {
                    Picker("Country", selection: $selectedCountry) {
                        ForEach(Country.all) { country in
                            Text("\(country.flag) \(country.name)")
                                .tag(country)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add Keywords")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addKeywords()
                        dismiss()
                    }
                    .disabled(keywords.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(minWidth: 400, minHeight: 350)
        .onAppear {
            selectedCountry = dataStore.selectedCountry
        }
    }

    private func addKeywords() {
        let keywordList = keywords
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        for keyword in keywordList {
            dataStore.addKeyword(keyword, to: app.id, countryCode: selectedCountry.code)
        }

        // Fetch rankings for new keywords
        Task {
            for keyword in keywordList {
                if let keywordObj = dataStore.trackedApps
                    .first(where: { $0.id == app.id })?
                    .keywords
                    .first(where: { $0.keyword == keyword.lowercased() }) {
                    if let rank = try? await AppStoreService.shared.searchKeywordRanking(
                        keyword: keyword,
                        appId: app.trackId,
                        country: selectedCountry.code
                    ) {
                        dataStore.updateKeywordRanking(keywordObj.id, for: app.id, rank: rank)
                    }
                }
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }
    }
}

// MARK: - macOS Color compatibility
#if os(macOS)
extension Color {
    init(nsColor: NSColor) {
        self.init(nsColor)
    }
}
#else
extension Color {
    init(nsColor: UIColor) {
        self.init(uiColor: nsColor)
    }
}

extension UIColor {
    static let controlBackgroundColor = UIColor.secondarySystemBackground
}
#endif

#Preview {
    MainView()
}
