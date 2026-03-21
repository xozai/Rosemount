// APActivity.swift
// Rosemount
//
// ActivityPub Activity types, Note, Attachment, Tag, and Visibility models.
// All types conform to Codable and Sendable.
// APActivityObject uses a custom Codable implementation to handle the
// polymorphic object field (string ID, embedded APActor, or embedded APNote).

import Foundation

// MARK: - APActivityType

/// The set of ActivityStreams / ActivityPub activity types used by Rosemount.
public enum APActivityType: String, Codable, Sendable {
    case create      = "Create"
    case follow      = "Follow"
    case like        = "Like"
    case announce    = "Announce"
    case delete      = "Delete"
    case update      = "Update"
    case undo        = "Undo"
    case accept      = "Accept"
    case reject      = "Reject"
    case block       = "Block"
    case add         = "Add"
    case remove      = "Remove"
    case emojiReact  = "EmojiReact"
}

// MARK: - APActivityObject

/// The `object` field of an `APActivity`.
///
/// In ActivityPub, an object may be:
/// - A plain `String` containing the URL / IRI of the referenced object.
/// - An embedded `APActor` document.
/// - An embedded `APNote` document.
///
/// Custom `Codable` picks the correct case by inspecting the `type` field
/// (when present) or falling back to a plain-string decode.
public enum APActivityObject: Sendable, Equatable {
    case string(String)
    case actor(APActor)
    case note(APNote)
}

extension APActivityObject: Codable {

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        // 1. Try decoding as a plain string (IRI reference).
        if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
            return
        }

        // 2. Peek at the "type" field to decide between APActor and APNote.
        let typeContainer = try decoder.container(keyedBy: TypePeekKey.self)
        let typeString = try typeContainer.decode(String.self, forKey: .type)

        switch typeString {
        case "Note":
            let note = try container.decode(APNote.self)
            self = .note(note)
        case "Person", "Group", "Service", "Application", "Organization":
            let actor = try container.decode(APActor.self)
            self = .actor(actor)
        default:
            // Unknown object type — store the raw id string if present,
            // otherwise use the type string so downstream code can handle it gracefully.
            if let id = try? typeContainer.decode(String.self, forKey: .id) {
                self = .string(id)
            } else {
                self = .string(typeString)
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .actor(let actor):
            try container.encode(actor)
        case .note(let note):
            try container.encode(note)
        }
    }

    // MARK: Private helpers

    private enum TypePeekKey: String, CodingKey {
        case type
        case id
    }
}

// MARK: - APActivityActor

/// The `actor` field of an `APActivity` — either a URL string or an embedded actor document.
public enum APActivityActor: Codable, Sendable, Equatable {
    case string(String)
    case actor(APActor)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) {
            self = .string(s)
            return
        }
        let actor = try container.decode(APActor.self)
        self = .actor(actor)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s):   try container.encode(s)
        case .actor(let a):    try container.encode(a)
        }
    }

    /// Returns the actor's URL string regardless of which case is active.
    public var urlString: String {
        switch self {
        case .string(let s):   return s
        case .actor(let a):    return a.id
        }
    }
}

// MARK: - APActivity

/// An ActivityPub Activity as sent between federated servers.
public struct APActivity: Sendable, Equatable {

    // MARK: JSON-LD

    /// The JSON-LD context string (normalised from string or array).
    public let context: String?

    // MARK: Core fields

    /// The URL identifier of this activity.
    public let id: String?
    /// The activity type.
    public let type: APActivityType
    /// The actor performing the activity.  May be a URL string or an embedded APActor.
    public let actor: APActivityActor?
    /// The object of the activity.
    public let object: APActivityObject?
    /// Recipient list (public / follower URLs).
    public let to: [String]?
    /// Carbon-copy recipient list.
    public let cc: [String]?
    /// ISO 8601 publication date-time.
    public let published: String?

    // MARK: Memberwise init

    public init(
        context: String? = "https://www.w3.org/ns/activitystreams",
        id: String? = nil,
        type: APActivityType,
        actor: APActivityActor? = nil,
        object: APActivityObject? = nil,
        to: [String]? = nil,
        cc: [String]? = nil,
        published: String? = nil
    ) {
        self.context   = context
        self.id        = id
        self.type      = type
        self.actor     = actor
        self.object    = object
        self.to        = to
        self.cc        = cc
        self.published = published
    }
}

// MARK: - APActivity + Codable

extension APActivity: Codable {

    public enum CodingKeys: String, CodingKey {
        case context   = "@context"
        case id
        case type
        case actor
        case object
        case to
        case cc
        case published
    }

    // MARK: Custom Decoding

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // @context — optional in nested activities; same string/array handling as APActor.
        if let s = try? container.decode(String.self, forKey: .context) {
            context = s
        } else if (try? container.nestedUnkeyedContainer(forKey: .context)) != nil {
            context = "https://www.w3.org/ns/activitystreams"
        } else {
            context = nil
        }

        id        = try container.decodeIfPresent(String.self,           forKey: .id)
        type      = try container.decode(APActivityType.self,            forKey: .type)
        actor     = try container.decodeIfPresent(APActivityActor.self,  forKey: .actor)
        object    = try container.decodeIfPresent(APActivityObject.self, forKey: .object)
        to        = try container.decodeIfPresent([String].self,         forKey: .to)
        cc        = try container.decodeIfPresent([String].self,         forKey: .cc)
        published = try container.decodeIfPresent(String.self,           forKey: .published)
    }

    // MARK: Custom Encoding

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(context,   forKey: .context)
        try container.encodeIfPresent(id,        forKey: .id)
        try container.encode(type,               forKey: .type)
        try container.encodeIfPresent(actor,     forKey: .actor)
        try container.encodeIfPresent(object,    forKey: .object)
        try container.encodeIfPresent(to,        forKey: .to)
        try container.encodeIfPresent(cc,        forKey: .cc)
        try container.encodeIfPresent(published, forKey: .published)
    }
}

// MARK: - APNote

/// An ActivityStreams `Note` object — the primary content type for statuses / toots.
public struct APNote: Codable, Sendable, Equatable {

    public let id: String
    /// Always `"Note"`.
    public let type: String
    /// URL of the Actor that authored this note.
    public let attributedTo: String
    /// HTML content of the note in the default language.
    public let content: String?
    /// Language-keyed map of HTML content, e.g. `["en": "<p>Hello</p>"]`.
    public let contentMap: [String: String]?
    /// Content-Warning / subject field.
    public let summary: String?
    /// When `true` the note is marked sensitive (CW collapsed).
    public let sensitive: Bool?
    /// Primary recipients.
    public let to: [String]?
    /// Carbon-copy recipients.
    public let cc: [String]?
    /// ID of the note this is a reply to, if any.
    public let inReplyTo: String?
    /// ISO 8601 publication timestamp.
    public let published: String?
    /// Human-readable URL for the note's permalink.
    public let url: String?
    /// File attachments (images, video, audio, documents).
    public let attachment: [APAttachment]?
    /// Mentions, hashtags, and emoji tags used in this note.
    public let tag: [APTag]?
    /// Reference to the replies collection for this note.
    public let replies: APCollectionRef?

    public enum CodingKeys: String, CodingKey {
        case id, type, attributedTo, content, contentMap, summary
        case sensitive, to, cc, inReplyTo, published, url
        case attachment, tag, replies
    }

    public init(
        id: String,
        type: String = "Note",
        attributedTo: String,
        content: String? = nil,
        contentMap: [String: String]? = nil,
        summary: String? = nil,
        sensitive: Bool? = nil,
        to: [String]? = nil,
        cc: [String]? = nil,
        inReplyTo: String? = nil,
        published: String? = nil,
        url: String? = nil,
        attachment: [APAttachment]? = nil,
        tag: [APTag]? = nil,
        replies: APCollectionRef? = nil
    ) {
        self.id = id
        self.type = type
        self.attributedTo = attributedTo
        self.content = content
        self.contentMap = contentMap
        self.summary = summary
        self.sensitive = sensitive
        self.to = to
        self.cc = cc
        self.inReplyTo = inReplyTo
        self.published = published
        self.url = url
        self.attachment = attachment
        self.tag = tag
        self.replies = replies
    }
}

// MARK: - APAttachment

/// A media attachment associated with an `APNote`.
public struct APAttachment: Codable, Sendable, Equatable {
    /// The ActivityStreams type, e.g. `"Document"`, `"Image"`, `"Video"`.
    public let type: String
    /// MIME type of the attached file.
    public let mediaType: String?
    /// URL of the attachment.
    public let url: String
    /// Alt-text / accessible name for the attachment.
    public let name: String?
    /// Pixel width of the media (images / video).
    public let width: Int?
    /// Pixel height of the media (images / video).
    public let height: Int?

    public init(
        type: String,
        mediaType: String? = nil,
        url: String,
        name: String? = nil,
        width: Int? = nil,
        height: Int? = nil
    ) {
        self.type = type
        self.mediaType = mediaType
        self.url = url
        self.name = name
        self.width = width
        self.height = height
    }
}

// MARK: - APTag

/// A tag referenced within an `APNote` — can be a Mention, Hashtag, or custom Emoji.
public struct APTag: Codable, Sendable, Equatable {
    /// `"Mention"`, `"Hashtag"`, or `"Emoji"`.
    public let type: String
    /// URL of the tagged resource (profile URL for mentions, tag page for hashtags).
    public let href: String?
    /// The display text of the tag, e.g. `"@alice@example.com"` or `"#swift"`.
    public let name: String?
    /// For `"Emoji"` tags: the image document.
    public let icon: APImage?

    public init(type: String, href: String? = nil, name: String? = nil, icon: APImage? = nil) {
        self.type = type
        self.href = href
        self.name = name
        self.icon = icon
    }
}

// MARK: - APCollectionRef

/// A lightweight reference to a Collection, used for the `replies` field on APNote.
/// May be a full inline collection or just an ID string pointing to one.
public struct APCollectionRef: Codable, Sendable, Equatable {
    public let id: String?
    public let type: String?
    public let first: String?

    public init(id: String? = nil, type: String? = nil, first: String? = nil) {
        self.id = id
        self.type = type
        self.first = first
    }
}

// MARK: - APVisibility

/// The audience visibility of an `APNote` or `APActivity`, derived from its `to`/`cc` arrays.
public enum APVisibility: String, Sendable, CaseIterable {
    /// Public timeline: `to` contains `https://www.w3.org/ns/activitystreams#Public`.
    case `public`
    /// Home timeline only: `cc` contains the public address; `to` contains the followers URL.
    case unlisted
    /// Followers only: `to` contains the followers collection; public URL absent.
    case followersOnly
    /// Direct message: addressed only to specific actors; no public/followers addresses.
    case direct

    // MARK: Constants

    private static let publicAddress      = "https://www.w3.org/ns/activitystreams#Public"
    private static let publicAddressShort = "as:Public"

    // MARK: Factory

    /// Compute visibility from a note's `to` and `cc` arrays and the owning actor's
    /// followers URL.
    ///
    /// - Parameters:
    ///   - to: The `to` field of the note/activity.
    ///   - cc: The `cc` field of the note/activity.
    ///   - followersURL: The followers collection URL of the authoring actor.
    public static func from(
        to: [String]?,
        cc: [String]?,
        followersURL: String?
    ) -> APVisibility {
        let toSet  = Set(to ?? [])
        let ccSet  = Set(cc ?? [])
        let allAddresses = toSet.union(ccSet)

        let isPublicInTo  = toSet.contains(publicAddress) || toSet.contains(publicAddressShort)
        let isPublicInCC  = ccSet.contains(publicAddress) || ccSet.contains(publicAddressShort)
        let followersInTo = followersURL.map { toSet.contains($0) } ?? false

        if isPublicInTo {
            return .public
        } else if isPublicInCC {
            return .unlisted
        } else if followersInTo || (followersURL.map { allAddresses.contains($0) } ?? false) {
            return .followersOnly
        } else {
            return .direct
        }
    }
}

// MARK: - APNote + APVisibility convenience

extension APNote {
    /// Returns the computed visibility for this note given the author's followers URL.
    public func visibility(followersURL: String?) -> APVisibility {
        APVisibility.from(to: to, cc: cc, followersURL: followersURL)
    }
}
