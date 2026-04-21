// Core/Events/Models/RosemountEvent.swift
// ActivityPub Event model (Mobilizon-compatible)

import CoreLocation
import Foundation

struct RosemountEvent: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let description: String
    let startDate: String
    let endDate: String?
    let timezone: String
    let location: EventLocation?
    let organizer: MastodonAccount
    let communityId: String?
    let communitySlug: String?
    let attendeeCount: Int
    let interestedCount: Int
    let myRsvp: RSVPStatus?
    let isOnline: Bool
    let onlineURL: String?
    let bannerURL: String?
    let createdAt: String
    let activityPubId: String

    enum CodingKeys: String, CodingKey {
        case id, title, description, timezone, location, organizer
        case startDate = "start_date"
        case endDate = "end_date"
        case communityId = "community_id"
        case communitySlug = "community_slug"
        case attendeeCount = "attendee_count"
        case interestedCount = "interested_count"
        case myRsvp = "my_rsvp"
        case isOnline = "is_online"
        case onlineURL = "online_url"
        case bannerURL = "banner_url"
        case createdAt = "created_at"
        case activityPubId = "activity_pub_id"
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: RosemountEvent, rhs: RosemountEvent) -> Bool { lhs.id == rhs.id }
}

struct EventLocation: Codable, Hashable {
    let name: String
    let address: String?
    let latitude: Double?
    let longitude: Double?

    var coordinate: CLLocationCoordinate2D? {
        guard let lat = latitude, let lon = longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

enum RSVPStatus: String, Codable, CaseIterable {
    case going, interested, notGoing = "not_going"

    var displayName: String {
        switch self {
        case .going: return "Going"
        case .interested: return "Interested"
        case .notGoing: return "Not Going"
        }
    }

    var systemImage: String {
        switch self {
        case .going: return "checkmark.circle.fill"
        case .interested: return "star.circle.fill"
        case .notGoing: return "xmark.circle.fill"
        }
    }

    var colorName: String {
        switch self {
        case .going: return "green"
        case .interested: return "orange"
        case .notGoing: return "red"
        }
    }
}

extension RosemountEvent {
    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let iso8601Plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    var startDateParsed: Date? {
        Self.iso8601.date(from: startDate) ?? Self.iso8601Plain.date(from: startDate)
    }

    var isPast: Bool { (startDateParsed ?? Date()) < Date() }

    var startDateFormatted: String {
        guard let date = startDateParsed else { return startDate }
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d 'at' h:mm a"
        return f.string(from: date)
    }

    var bannerImageURL: URL? {
        bannerURL.flatMap { URL(string: $0) }
    }

    var locationCoordinate: CLLocationCoordinate2D? {
        location?.coordinate
    }

    func withMyRsvp(_ newRsvp: RSVPStatus?) -> RosemountEvent {
        RosemountEvent(
            id: id, title: title, description: description,
            startDate: startDate, endDate: endDate, timezone: timezone,
            location: location, organizer: organizer,
            communityId: communityId, communitySlug: communitySlug,
            attendeeCount: attendeeCount, interestedCount: interestedCount,
            myRsvp: newRsvp,
            isOnline: isOnline, onlineURL: onlineURL, bannerURL: bannerURL,
            createdAt: createdAt, activityPubId: activityPubId
        )
    }
}
