// APActor.swift
// Rosemount
//
// ActivityPub Actor model supporting Person, Group, Service, Application, and Organization types.
// Conforms to the ActivityPub / ActivityStreams 2.0 specification.
// JSON-LD Codable with custom decoding to handle polymorphic @context field.

import Foundation

// MARK: - APActorType

/// The type of ActivityPub Actor as defined in ActivityStreams 2.0.
public enum APActorType: String, Codable, Sendable {
    case person       = "Person"
    case group        = "Group"
    case service      = "Service"
    case application  = "Application"
    case organization = "Organization"
}

// MARK: - APPublicKey

/// The public key associated with an ActivityPub Actor, used for HTTP Signature verification.
public struct APPublicKey: Codable, Sendable, Equatable {
    /// The URL identifier of the key, typically `{actorId}#main-key`.
    public let id: String
    /// The URL of the Actor that owns this key.
    public let owner: String
    /// The PEM-encoded RSA public key.
    public let publicKeyPem: String

    public enum CodingKeys: String, CodingKey {
        case id
        case owner
        case publicKeyPem
    }
}

// MARK: - APImage

/// Represents an image document attached to an Actor (icon or header image).
public struct APImage: Codable, Sendable, Equatable {
    /// The ActivityStreams type, typically `"Image"`.
    public let type: String
    /// The MIME type of the image, e.g. `"image/png"`.
    public let mediaType: String?
    /// The URL string pointing to the image resource.
    public let url: String

    public enum CodingKeys: String, CodingKey {
        case type
        case mediaType
        case url
    }

    public init(type: String = "Image", mediaType: String? = nil, url: String) {
        self.type = type
        self.mediaType = mediaType
        self.url = url
    }
}

// MARK: - APEndpoints

/// Service endpoints advertised by an Actor.
public struct APEndpoints: Codable, Sendable, Equatable {
    /// The shared inbox URL for the Actor's instance, used for delivery optimisation.
    public let sharedInbox: String?

    public enum CodingKeys: String, CodingKey {
        case sharedInbox
    }
}

// MARK: - APActor

/// Full ActivityPub Actor model covering the fields common to all actor types.
///
/// Implements custom `Decodable` logic so that the JSON-LD `@context` property
/// can be decoded regardless of whether the server sends it as a plain `String`
/// or as a heterogeneous `[Any]` array (the canonical ActivityPub context plus
/// extension context objects / URLs).
public struct APActor: Sendable, Equatable {

    // MARK: JSON-LD

    /// The JSON-LD context.  Stored as a plain string for the common case; the
    /// custom decoder collapses array forms to the primary context URL.
    public let context: String

    // MARK: Core identity

    /// The canonical URL identifier of this Actor.
    public let id: String
    /// The `APActorType` of this Actor.
    public let type: APActorType
    /// The short username portion of the Actor's handle (without `@` or domain).
    public let preferredUsername: String
    /// The display name of the Actor.
    public let name: String?
    /// An HTML summary / bio for this Actor.
    public let summary: String?
    /// A human-readable URL for this Actor's profile page.
    public let url: String?

    // MARK: Collection endpoints

    /// URL of this Actor's inbox.
    public let inbox: String
    /// URL of this Actor's outbox.
    public let outbox: String
    /// URL of this Actor's followers collection.
    public let followers: String?
    /// URL of this Actor's following collection.
    public let following: String?

    // MARK: Cryptographic identity

    /// The public key used for HTTP Signature verification.
    public let publicKey: APPublicKey?

    // MARK: Media

    /// The Actor's avatar image.
    public let icon: APImage?
    /// The Actor's header / banner image.
    public let image: APImage?

    // MARK: Service endpoints

    /// Additional service endpoints, e.g. shared inbox.
    public let endpoints: APEndpoints?

    // MARK: Metadata flags

    /// When `true`, the Actor must manually approve follow requests.
    public let manuallyApprovesFollowers: Bool?
    /// When `true`, the Actor opts in to directory discovery.
    public let discoverable: Bool?
    /// ISO 8601 date-time string of when the Actor account was created.
    public let published: String?

    // MARK: - Computed properties

    /// Returns the full Mastodon-style handle in the form `@preferredUsername@host`.
    public var handle: String {
        "@\(preferredUsername)@\(instanceHost)"
    }

    /// Extracts the host component from the `id` URL.
    /// Returns an empty string if `id` is not a valid URL.
    public var instanceHost: String {
        URL(string: id)?.host ?? ""
    }

    // MARK: - Memberwise init

    public init(
        context: String = "https://www.w3.org/ns/activitystreams",
        id: String,
        type: APActorType,
        preferredUsername: String,
        name: String? = nil,
        summary: String? = nil,
        url: String? = nil,
        inbox: String,
        outbox: String,
        followers: String? = nil,
        following: String? = nil,
        publicKey: APPublicKey? = nil,
        icon: APImage? = nil,
        image: APImage? = nil,
        endpoints: APEndpoints? = nil,
        manuallyApprovesFollowers: Bool? = nil,
        discoverable: Bool? = nil,
        published: String? = nil
    ) {
        self.context = context
        self.id = id
        self.type = type
        self.preferredUsername = preferredUsername
        self.name = name
        self.summary = summary
        self.url = url
        self.inbox = inbox
        self.outbox = outbox
        self.followers = followers
        self.following = following
        self.publicKey = publicKey
        self.icon = icon
        self.image = image
        self.endpoints = endpoints
        self.manuallyApprovesFollowers = manuallyApprovesFollowers
        self.discoverable = discoverable
        self.published = published
    }
}

// MARK: - APActor + Codable

extension APActor: Codable {

    public enum CodingKeys: String, CodingKey {
        case context                   = "@context"
        case id
        case type
        case preferredUsername
        case name
        case summary
        case url
        case inbox
        case outbox
        case followers
        case following
        case publicKey
        case icon
        case image
        case endpoints
        case manuallyApprovesFollowers
        case discoverable
        case published
    }

    // MARK: Custom Decoding

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // ------------------------------------------------------------------
        // @context: may arrive as a plain String OR as a heterogeneous array
        // that begins with the ActivityStreams context URL followed by
        // extension maps/URLs.  We normalise to the primary URL string.
        // ------------------------------------------------------------------
        if let contextString = try? container.decode(String.self, forKey: .context) {
            context = contextString
        } else {
            // Attempt to decode as an array; extract the first String element.
            var arrayContainer = try container.nestedUnkeyedContainer(forKey: .context)
            var firstString: String?
            while !arrayContainer.isAtEnd {
                // Try to pull a String; if it's an object, skip it.
                if let s = try? arrayContainer.decode(String.self) {
                    if firstString == nil { firstString = s }
                } else {
                    // Skip non-string elements (extension context objects).
                    _ = try? arrayContainer.decode(APContextPlaceholder.self)
                }
            }
            context = firstString ?? "https://www.w3.org/ns/activitystreams"
        }

        id                   = try container.decode(String.self,         forKey: .id)
        type                 = try container.decode(APActorType.self,    forKey: .type)
        preferredUsername    = try container.decode(String.self,         forKey: .preferredUsername)
        name                 = try container.decodeIfPresent(String.self, forKey: .name)
        summary              = try container.decodeIfPresent(String.self, forKey: .summary)
        url                  = try container.decodeIfPresent(String.self, forKey: .url)
        inbox                = try container.decode(String.self,         forKey: .inbox)
        outbox               = try container.decode(String.self,         forKey: .outbox)
        followers            = try container.decodeIfPresent(String.self, forKey: .followers)
        following            = try container.decodeIfPresent(String.self, forKey: .following)
        publicKey            = try container.decodeIfPresent(APPublicKey.self,   forKey: .publicKey)
        icon                 = try container.decodeIfPresent(APImage.self,       forKey: .icon)
        image                = try container.decodeIfPresent(APImage.self,       forKey: .image)
        endpoints            = try container.decodeIfPresent(APEndpoints.self,   forKey: .endpoints)
        manuallyApprovesFollowers = try container.decodeIfPresent(Bool.self, forKey: .manuallyApprovesFollowers)
        discoverable         = try container.decodeIfPresent(Bool.self, forKey: .discoverable)
        published            = try container.decodeIfPresent(String.self, forKey: .published)
    }

    // MARK: Custom Encoding

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(context,             forKey: .context)
        try container.encode(id,                  forKey: .id)
        try container.encode(type,                forKey: .type)
        try container.encode(preferredUsername,   forKey: .preferredUsername)
        try container.encodeIfPresent(name,       forKey: .name)
        try container.encodeIfPresent(summary,    forKey: .summary)
        try container.encodeIfPresent(url,        forKey: .url)
        try container.encode(inbox,               forKey: .inbox)
        try container.encode(outbox,              forKey: .outbox)
        try container.encodeIfPresent(followers,  forKey: .followers)
        try container.encodeIfPresent(following,  forKey: .following)
        try container.encodeIfPresent(publicKey,  forKey: .publicKey)
        try container.encodeIfPresent(icon,       forKey: .icon)
        try container.encodeIfPresent(image,      forKey: .image)
        try container.encodeIfPresent(endpoints,  forKey: .endpoints)
        try container.encodeIfPresent(manuallyApprovesFollowers, forKey: .manuallyApprovesFollowers)
        try container.encodeIfPresent(discoverable, forKey: .discoverable)
        try container.encodeIfPresent(published,  forKey: .published)
    }
}

// MARK: - Private helpers

/// A throwaway decodable used to skip unknown objects inside the @context array.
private struct APContextPlaceholder: Decodable {}
