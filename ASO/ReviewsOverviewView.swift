//
//  ReviewsOverviewView.swift
//  ASO
//

import SwiftUI

struct ReviewsOverviewView: View {
    @EnvironmentObject var dataStore: DataStore
    @Binding var selectedApp: TrackedApp?
    @State private var reviews: [String: [AppReview]] = [:]
    @State private var isLoading = false
    @State private var selectedRating: Int? = nil
    @State private var selectedCountry: Country?

    var allReviews: [(app: TrackedApp, review: AppReview)] {
        var result: [(app: TrackedApp, review: AppReview)] = []
        for app in dataStore.trackedApps {
            if let appReviews = reviews[app.bundleId] {
                for review in appReviews {
                    result.append((app: app, review: review))
                }
            }
        }
        return result.sorted { $0.review.date > $1.review.date }
    }

    var filteredReviews: [(app: TrackedApp, review: AppReview)] {
        var filtered = allReviews

        if let rating = selectedRating {
            filtered = filtered.filter { $0.review.rating == rating }
        }

        if let country = selectedCountry {
            filtered = filtered.filter { $0.review.countryCode == country.code }
        }

        return filtered
    }

    var body: some View {
        Group {
            if dataStore.trackedApps.isEmpty {
                emptyState
            } else {
                reviewsList
            }
        }
        .navigationTitle("Reviews")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("All Ratings") {
                        selectedRating = nil
                    }
                    Divider()
                    ForEach((1...5).reversed(), id: \.self) { rating in
                        Button(action: { selectedRating = rating }) {
                            HStack {
                                Text(String(repeating: "★", count: rating) + String(repeating: "☆", count: 5 - rating))
                                if selectedRating == rating {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "star")
                }
            }

            ToolbarItem(placement: .primaryAction) {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Button(action: loadAllReviews) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
        .onAppear {
            if reviews.isEmpty {
                loadAllReviews()
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Apps", systemImage: "star.bubble")
        } description: {
            Text("Add apps to track their reviews across all App Store countries.")
        }
    }

    private var reviewsList: some View {
        List {
            // Summary Section
            Section {
                HStack {
                    VStack(alignment: .leading) {
                        Text("\(allReviews.count)")
                            .font(.title)
                            .fontWeight(.bold)
                        Text("Reviews Loaded")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .leading) {
                        if let avg = averageRating {
                            HStack(spacing: 2) {
                                Text(String(format: "%.1f", avg))
                                    .font(.title)
                                    .fontWeight(.bold)
                                Image(systemName: "star.fill")
                                    .foregroundColor(.yellow)
                            }
                        } else {
                            Text("-")
                                .font(.title)
                                .fontWeight(.bold)
                        }
                        Text("Average")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .leading) {
                        Text("\(positiveReviews)")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                        Text("Positive (4-5★)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }

            // Rating Distribution
            if !allReviews.isEmpty {
                Section("Rating Distribution") {
                    VStack(spacing: 8) {
                        ForEach((1...5).reversed(), id: \.self) { rating in
                            RatingBar(
                                rating: rating,
                                count: reviewCount(for: rating),
                                total: allReviews.count
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            // Reviews
            Section("Recent Reviews") {
                if filteredReviews.isEmpty {
                    if isLoading {
                        HStack {
                            Spacer()
                            ProgressView("Loading reviews...")
                            Spacer()
                        }
                        .padding()
                    } else {
                        ContentUnavailableView {
                            Label("No Reviews", systemImage: "text.bubble")
                        } description: {
                            Text("Tap refresh to load reviews from the App Store.")
                        }
                    }
                } else {
                    ForEach(filteredReviews.prefix(50), id: \.review.id) { item in
                        ReviewOverviewRow(app: item.app, review: item.review)
                            .onTapGesture {
                                selectedApp = item.app
                            }
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    private var averageRating: Double? {
        guard !allReviews.isEmpty else { return nil }
        let sum = allReviews.reduce(0) { $0 + $1.review.rating }
        return Double(sum) / Double(allReviews.count)
    }

    private var positiveReviews: Int {
        allReviews.filter { $0.review.rating >= 4 }.count
    }

    private func reviewCount(for rating: Int) -> Int {
        allReviews.filter { $0.review.rating == rating }.count
    }

    private func loadAllReviews() {
        isLoading = true

        Task {
            for app in dataStore.trackedApps {
                do {
                    let appReviews = try await AppStoreService.shared.fetchReviews(
                        appId: app.trackId,
                        country: dataStore.selectedCountry.code
                    )
                    reviews[app.bundleId] = appReviews
                } catch {
                    print("Failed to load reviews for \(app.trackName): \(error)")
                }
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
            isLoading = false
        }
    }
}

// MARK: - Rating Bar
struct RatingBar: View {
    let rating: Int
    let count: Int
    let total: Int

    var percentage: Double {
        guard total > 0 else { return 0 }
        return Double(count) / Double(total)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("\(rating)★")
                .font(.caption)
                .frame(width: 30, alignment: .trailing)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))

                    RoundedRectangle(cornerRadius: 4)
                        .fill(ratingColor)
                        .frame(width: geometry.size.width * percentage)
                }
            }
            .frame(height: 16)

            Text("\(count)")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
    }

    private var ratingColor: Color {
        switch rating {
        case 5: return .green
        case 4: return .green.opacity(0.7)
        case 3: return .yellow
        case 2: return .orange
        default: return .red
        }
    }
}

// MARK: - Review Overview Row
struct ReviewOverviewRow: View {
    let app: TrackedApp
    let review: AppReview

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                AsyncImage(url: URL(string: app.artworkUrl)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.3))
                }
                .frame(width: 28, height: 28)
                .cornerRadius(6)

                Text(app.trackName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Spacer()

                HStack(spacing: 2) {
                    ForEach(0..<5) { index in
                        Image(systemName: index < review.rating ? "star.fill" : "star")
                            .font(.caption2)
                            .foregroundColor(.yellow)
                    }
                }

                if let country = Country.country(for: review.countryCode) {
                    Text(country.flag)
                        .font(.caption)
                }
            }

            Text(review.title)
                .font(.subheadline)
                .fontWeight(.medium)

            Text(review.content)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(3)

            HStack {
                Text(review.author)
                    .font(.caption2)
                    .foregroundColor(.secondary)

                if let version = review.version {
                    Text("• v\(version)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(review.date, style: .relative)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ReviewsOverviewView(selectedApp: .constant(nil))
        .environmentObject(DataStore.shared)
}
