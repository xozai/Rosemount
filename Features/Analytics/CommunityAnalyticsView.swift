// Features/Analytics/CommunityAnalyticsView.swift
// Community analytics dashboard with Swift Charts

import Charts
import SwiftUI

@Observable
@MainActor
final class CommunityAnalyticsViewModel {
    var metrics: CommunityMetrics?
    var period: AnalyticsPeriod = .month
    var isLoading: Bool = false
    var error: Error?
    private var client: CommunityAnalyticsAPIClient?
    private var communitySlug: String = ""

    func setup(communitySlug: String, credential: AccountCredential) {
        self.communitySlug = communitySlug
        client = CommunityAnalyticsAPIClient(instanceURL: credential.instanceURL, accessToken: credential.accessToken)
    }

    func load() async {
        guard let client else { return }
        isLoading = true
        error = nil
        do {
            metrics = try await client.metrics(communitySlug: communitySlug, period: period)
        } catch {
            self.error = error
        }
        isLoading = false
    }
}

struct CommunityAnalyticsView: View {
    let communitySlug: String
    @State private var viewModel = CommunityAnalyticsViewModel()
    @Environment(AuthManager.self) private var authManager

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.metrics == nil {
                ProgressView("Loading analytics…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let metrics = viewModel.metrics {
                analyticsContent(metrics)
            } else {
                ContentUnavailableView("No Analytics", systemImage: "chart.bar.xaxis", description: Text("Analytics data is not available yet."))
            }
        }
        .navigationTitle("Analytics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Picker("Period", selection: $viewModel.period) {
                    ForEach(AnalyticsPeriod.allCases) { p in
                        Text(p.displayName).tag(p)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: viewModel.period) { _, _ in Task { await viewModel.load() } }
            }
        }
        .task {
            if let account = authManager.activeAccount {
                viewModel.setup(communitySlug: communitySlug, credential: account)
                await viewModel.load()
            }
        }
        .refreshable { await viewModel.load() }
    }

    @ViewBuilder
    private func analyticsContent(_ m: CommunityMetrics) -> some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                // Summary cards
                StatCardsRow(metrics: m)

                // Activity chart
                ActivityChartCard(dailyActivity: m.dailyActivity)

                // Top posts
                if !m.topPosts.isEmpty {
                    TopPostsCard(topPosts: m.topPosts)
                }

                // Top contributors
                if !m.topContributors.isEmpty {
                    TopContributorsCard(contributors: m.topContributors)
                }

                // Retention ring
                RetentionCard(retention: m.memberRetention, activeMembers: m.activeMembers, totalMembers: m.memberCount)
            }
            .padding()
        }
    }
}

// MARK: - Stat Cards Row

struct StatCardsRow: View {
    let metrics: CommunityMetrics

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatCard(title: "Members", value: "\(metrics.memberCount)", change: metrics.memberGrowth, icon: "person.2.fill", color: .blue)
            StatCard(title: "Posts", value: "\(metrics.postCount)", change: metrics.postGrowth, icon: "square.and.pencil", color: .purple)
            StatCard(title: "Reactions", value: "\(metrics.reactionCount)", change: nil, icon: "heart.fill", color: .pink)
            StatCard(title: "New Members", value: "\(metrics.newMembersThisPeriod)", change: nil, icon: "person.badge.plus", color: .green)
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let change: Double?
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon).foregroundStyle(color)
                Spacer()
                if let change {
                    HStack(spacing: 2) {
                        Image(systemName: change >= 0 ? "arrow.up" : "arrow.down")
                        Text("\(abs(Int(change)))%")
                    }
                    .font(.caption2.bold())
                    .foregroundStyle(change >= 0 ? .green : .red)
                }
            }
            Text(value).font(.title2.bold())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}

// MARK: - Activity Chart

struct ActivityChartCard: View {
    let dailyActivity: [DailyActivity]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Activity").font(.headline)

            Chart(dailyActivity) { day in
                BarMark(
                    x: .value("Date", day.dateValue ?? Date()),
                    y: .value("Posts", day.posts)
                )
                .foregroundStyle(.blue.opacity(0.8))
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .frame(height: 180)
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}

// MARK: - Top Posts

struct TopPostsCard: View {
    let topPosts: [TopPost]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top Posts").font(.headline)
            ForEach(topPosts.prefix(3)) { post in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "star.fill").foregroundStyle(.yellow).font(.caption)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(post.content).font(.subheadline).lineLimit(2)
                        HStack(spacing: 12) {
                            Label("\(post.favouritesCount)", systemImage: "heart").font(.caption).foregroundStyle(.secondary)
                            Label("\(post.reblogsCount)", systemImage: "arrow.2.squarepath").font(.caption).foregroundStyle(.secondary)
                            Label("\(post.repliesCount)", systemImage: "bubble.right").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if post.id != topPosts.prefix(3).last?.id { Divider() }
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}

// MARK: - Top Contributors

struct TopContributorsCard: View {
    let contributors: [TopContributor]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top Contributors").font(.headline)
            ForEach(contributors.prefix(5)) { contributor in
                HStack(spacing: 10) {
                    AsyncImage(url: URL(string: contributor.account.avatar)) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        Circle().fill(.gray.opacity(0.2))
                    }
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(contributor.account.displayName).font(.subheadline.bold())
                        Text("@\(contributor.account.acct)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(contributor.postCount) posts").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}

// MARK: - Retention Ring

struct RetentionCard: View {
    let retention: Double
    let activeMembers: Int
    let totalMembers: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Member Retention").font(.headline)
            HStack {
                // Donut chart
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 16)
                    Circle()
                        .trim(from: 0, to: min(retention / 100.0, 1.0))
                        .stroke(
                            AngularGradient(colors: [.blue, .purple], center: .center),
                            style: StrokeStyle(lineWidth: 16, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.8), value: retention)
                    VStack(spacing: 2) {
                        Text("\(Int(retention))%").font(.title3.bold())
                        Text("active").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 100, height: 100)

                VStack(alignment: .leading, spacing: 8) {
                    HStack { Circle().fill(.blue).frame(width: 10, height: 10); Text("Active: \(activeMembers)").font(.subheadline) }
                    HStack { Circle().fill(.secondary.opacity(0.3)).frame(width: 10, height: 10); Text("Inactive: \(totalMembers - activeMembers)").font(.subheadline) }
                }
                .padding(.leading)
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}
