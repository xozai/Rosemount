// Core/Analytics/CommunityAnalyticsService.swift
// Community analytics data models and API client

import Foundation

// MARK: - Models

struct CommunityMetrics: Codable {
    let communitySlug: String
    let period: AnalyticsPeriod
    let memberCount: Int
    let memberGrowth: Double          // % change from previous period
    let activeMembers: Int            // posted or reacted in period
    let postCount: Int
    let postGrowth: Double
    let reactionCount: Int
    let boostCount: Int
    let topPosts: [TopPost]
    let dailyActivity: [DailyActivity]
    let memberRetention: Double       // % of members who were active
    let newMembersThisPeriod: Int
    let topContributors: [TopContributor]

    enum CodingKeys: String, CodingKey {
        case period
        case memberCount = "member_count"
        case memberGrowth = "member_growth"
        case activeMembers = "active_members"
        case postCount = "post_count"
        case postGrowth = "post_growth"
        case reactionCount = "reaction_count"
        case boostCount = "boost_count"
        case topPosts = "top_posts"
        case dailyActivity = "daily_activity"
        case memberRetention = "member_retention"
        case newMembersThisPeriod = "new_members_this_period"
        case topContributors = "top_contributors"
        case communitySlug = "community_slug"
    }
}

enum AnalyticsPeriod: String, Codable, CaseIterable, Identifiable {
    case week = "7d"
    case month = "30d"
    case quarter = "90d"

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .week: return "7 Days"
        case .month: return "30 Days"
        case .quarter: return "90 Days"
        }
    }
}

struct DailyActivity: Codable, Identifiable {
    let date: String     // "2024-03-15"
    let posts: Int
    let members: Int
    let reactions: Int

    var id: String { date }
    var dateValue: Date? {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.date(from: date)
    }
}

struct TopPost: Codable, Identifiable {
    let id: String
    let content: String
    let authorHandle: String
    let favouritesCount: Int
    let reblogsCount: Int
    let repliesCount: Int

    enum CodingKeys: String, CodingKey {
        case id, content
        case authorHandle = "author_handle"
        case favouritesCount = "favourites_count"
        case reblogsCount = "reblogs_count"
        case repliesCount = "replies_count"
    }

    var engagementScore: Int { favouritesCount + reblogsCount * 2 + repliesCount }
}

struct TopContributor: Codable, Identifiable {
    let id: String
    let account: MastodonAccount
    let postCount: Int
    let reactionCount: Int

    enum CodingKeys: String, CodingKey {
        case id, account
        case postCount = "post_count"
        case reactionCount = "reaction_count"
    }
}

// MARK: - API Client

actor CommunityAnalyticsAPIClient {
    private let instanceURL: URL
    private let accessToken: String

    init(instanceURL: URL, accessToken: String) {
        self.instanceURL = instanceURL
        self.accessToken = accessToken
    }

    func metrics(communitySlug: String, period: AnalyticsPeriod) async throws -> CommunityMetrics {
        var req = URLRequest(url: instanceURL.appendingPathComponent("api/v1/communities/\(communitySlug)/analytics?period=\(period.rawValue)"))
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        return try dec.decode(CommunityMetrics.self, from: data)
    }
}
