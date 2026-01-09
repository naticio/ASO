//
//  MainView.swift
//  ASO
//

import SwiftUI

struct MainView: View {
    @StateObject private var dataStore = DataStore.shared
    @State private var selectedNavigation: NavigationItem? = .dashboard
    @State private var selectedApp: TrackedApp?
    @State private var showingAddApp = false
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } content: {
            contentView
        } detail: {
            detailView
        }
        .environmentObject(dataStore)
        .sheet(isPresented: $showingAddApp) {
            AppSearchSheet()
                .environmentObject(dataStore)
        }
    }

    // MARK: - Sidebar
    private var sidebar: some View {
        List(selection: $selectedNavigation) {
            Section {
                NavigationLink(value: NavigationItem.dashboard) {
                    Label("Dashboard", systemImage: "chart.bar.fill")
                }

                NavigationLink(value: NavigationItem.apps) {
                    Label("Apps", systemImage: "apps.iphone")
                }

                NavigationLink(value: NavigationItem.keywords) {
                    Label("Keywords", systemImage: "magnifyingglass")
                }

                NavigationLink(value: NavigationItem.reviews) {
                    Label("Reviews", systemImage: "star.bubble")
                }
            }

            Section {
                NavigationLink(value: NavigationItem.settings) {
                    Label("Settings", systemImage: "gear")
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("ASO")
        #if os(macOS)
        .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 250)
        #endif
        .toolbar {
            #if os(macOS)
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingAddApp = true }) {
                    Image(systemName: "plus")
                }
                .help("Add App")
            }
            #else
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingAddApp = true }) {
                    Image(systemName: "plus")
                }
            }
            #endif
        }
    }

    // MARK: - Content View
    @ViewBuilder
    private var contentView: some View {
        switch selectedNavigation {
        case .dashboard:
            DashboardView(selectedApp: $selectedApp)
        case .apps:
            AppsListView(selectedApp: $selectedApp, showingAddApp: $showingAddApp)
        case .keywords:
            KeywordsOverviewView(selectedApp: $selectedApp)
        case .reviews:
            ReviewsOverviewView(selectedApp: $selectedApp)
        case .settings:
            SettingsView()
        case .none:
            ContentUnavailableView("Select a Section", systemImage: "sidebar.left", description: Text("Choose a section from the sidebar"))
        }
    }

    // MARK: - Detail View
    @ViewBuilder
    private var detailView: some View {
        if let app = selectedApp {
            AppDetailView(app: binding(for: app))
        } else {
            ContentUnavailableView("Select an App", systemImage: "app.badge.checkmark", description: Text("Choose an app to view details"))
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

// MARK: - Dashboard View
struct DashboardView: View {
    @EnvironmentObject var dataStore: DataStore
    @Binding var selectedApp: TrackedApp?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Stats Cards
                statsSection

                // Recent Activity
                if !dataStore.trackedApps.isEmpty {
                    recentAppsSection
                }
            }
            .padding()
        }
        .navigationTitle("Dashboard")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if dataStore.isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Button(action: {
                        Task {
                            await dataStore.refreshAllRankings()
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh All Rankings")
                }
            }
        }
    }

    private var statsSection: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 16) {
            StatCard(title: "Apps", value: "\(dataStore.trackedApps.count)", icon: "apps.iphone", color: .blue)
            StatCard(title: "Keywords", value: "\(dataStore.totalKeywords)", icon: "magnifyingglass", color: .green)
            StatCard(title: "Avg Rating", value: dataStore.averageRating.map { String(format: "%.1f", $0) } ?? "N/A", icon: "star.fill", color: .yellow)
            StatCard(title: "Reviews", value: formatNumber(dataStore.totalReviews), icon: "text.bubble", color: .purple)
        }
    }

    private var recentAppsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tracked Apps")
                .font(.headline)

            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 280, maximum: 400))
            ], spacing: 12) {
                ForEach(dataStore.trackedApps.sorted { $0.lastUpdated > $1.lastUpdated }) { app in
                    AppCard(app: app)
                        .onTapGesture {
                            selectedApp = app
                        }
                }
            }
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

// MARK: - Stat Card
struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Spacer()
            }
            Text(value)
                .font(.title)
                .fontWeight(.bold)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.secondarySystemBackground)
        .cornerRadius(12)
    }
}

// MARK: - App Card
struct AppCard: View {
    let app: TrackedApp

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: app.artworkUrl)) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } placeholder: {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.3))
            }
            .frame(width: 50, height: 50)
            .cornerRadius(12)

            VStack(alignment: .leading, spacing: 4) {
                Text(app.trackName)
                    .font(.headline)
                    .lineLimit(1)
                Text(app.sellerName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Label("\(app.keywords.count)", systemImage: "magnifyingglass")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    if let lastRating = app.ratingSnapshots.last {
                        Label(String(format: "%.1f", lastRating.rating), systemImage: "star.fill")
                            .font(.caption2)
                            .foregroundColor(.yellow)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.secondarySystemBackground)
        .cornerRadius(12)
    }
}

#Preview {
    MainView()
}
