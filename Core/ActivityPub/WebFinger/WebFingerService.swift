// WebFingerService.swift
// Rosemount
//
// WebFinger (RFC 7033) resolution service for mapping Mastodon-style handles
// (@user@instance.social) to ActivityPub Actor URLs.
//
// Resolved actors are cached in-memory using NSCache with a 5-minute TTL so
// that repeated lookups within a session do not generate redundant network traffic.

import Foundation

// MARK: - WebFingerError

/// Errors thrown by `WebFingerService`.
public enum WebFingerError: Error, Sendable, LocalizedError {
    /// The handle string could not be parsed into a user / host pair.
    case invalidHandle(String)
    /// The WebFinger endpoint returned an empty or non-200 response.
    case notFound(String)
    /// The WebFinger response contained no link with `rel=self` and the ActivityPub media type.
    case noActivityPubLink
    /// A network-level error occurred; the underlying error is attached.
    case networkError(Error)

    public var errorDescription: String? {
        switch self {
        case .invalidHandle(let h):
            return "'\(h)' is not a valid ActivityPub handle. Expected format: @user@host"
        case .notFound(let resource):
            return "WebFinger resource not found: \(resource)"
        case .noActivityPubLink:
            return "The WebFinger response did not include an ActivityPub self-link."
        case .networkError(let underlying):
            return "Network error: \(underlying.localizedDescription)"
        }
    }
}

// MARK: - WebFingerLink

/// A single link object within a WebFinger JRD response.
public struct WebFingerLink: Codable, Sendable, Equatable {
    /// The link relation type (e.g. `"self"`, `"http://webfinger.net/rel/profile-page"`).
    public let rel: String
    /// The MIME type of the linked resource (e.g. `"application/activity+json"`).
    public let type: String?
    /// The href URL of the linked resource.
    public let href: String?
    /// Human-readable titles keyed by BCP 47 language tag.
    public let titles: [String: String]?
    /// Opaque property bag (implementation-defined).
    public let properties: [String: String?]?

    public init(
        rel: String,
        type: String? = nil,
        href: String? = nil,
        titles: [String: String]? = nil,
        properties: [String: String?]? = nil
    ) {
        self.rel = rel
        self.type = type
        self.href = href
        self.titles = titles
        self.properties = properties
    }
}

// MARK: - WebFingerResource

/// The JSON Resource Descriptor (JRD) returned by a WebFinger endpoint.
public struct WebFingerResource: Codable, Sendable, Equatable {
    /// The `acct:` URI that was looked up (e.g. `"acct:alice@mastodon.social"`).
    public let subject: String
    /// Alternative URIs for the same subject.
    public let aliases: [String]?
    /// The set of links describing the subject.
    public let links: [WebFingerLink]
}

// MARK: - APActorWrapper (NSCache value shim)

/// `NSCache` requires its values to be reference types.  This class wraps `APActor`
/// together with the time at which it was cached so that the TTL can be enforced.
final class APActorWrapper: @unchecked Sendable {
    let actor: APActor
    let cachedAt: Date

    init(actor: APActor, cachedAt: Date = Date()) {
        self.actor = actor
        self.cachedAt = cachedAt
    }
}

// MARK: - WebFingerService

/// An actor that resolves WebFinger handles to `APActor` objects.
///
/// Usage:
/// ```swift
/// let service = WebFingerService()
/// let actor = try await service.resolve(handle: "@alice@mastodon.social")
/// ```
public actor WebFingerService {

    // MARK: - Constants

    private static let activityPubMediaType = "application/activity+json"
    private static let selfRel              = "self"
    private static let cacheTTL: TimeInterval = 5 * 60   // 5 minutes

    // MARK: - Dependencies

    private let urlSession: URLSession
    private let decoder: JSONDecoder

    // MARK: - Cache

    /// In-memory cache keyed by actor URL string.
    /// `NSCache` automatically evicts entries under memory pressure.
    private let cache = NSCache<NSString, APActorWrapper>()

    // MARK: - Init

    public init(urlSession: URLSession = .init(configuration: .ephemeral)) {
        self.urlSession = urlSession
        self.decoder = JSONDecoder()
        self.cache.countLimit = 256
    }

    // MARK: - Public API

    /// Resolves a Mastodon-style handle to an ActivityPub Actor URL.
    ///
    /// - Parameter handle: A handle such as `"@alice@mastodon.social"` or `"alice@mastodon.social"`.
    /// - Returns: The `URL` of the actor's ActivityPub document.
    /// - Throws: `WebFingerError` on invalid input or lookup failure.
    public func resolve(handle: String) async throws -> URL {
        // Strip a leading '@' if present, then split on '@'.
        let stripped = handle.hasPrefix("@") ? String(handle.dropFirst()) : handle
        let parts    = stripped.split(separator: "@", maxSplits: 1)

        guard parts.count == 2 else {
            throw WebFingerError.invalidHandle(handle)
        }

        let user = String(parts[0])
        let host = String(parts[1])

        guard !user.isEmpty, !host.isEmpty else {
            throw WebFingerError.invalidHandle(handle)
        }

        let acctResource = "acct:\(user)@\(host)"
        let resource     = try webFingerURL(host: host, resource: acctResource)

        let jrd = try await fetchWebFingerResource(at: resource)

        // Find the self-link with the ActivityPub media type.
        guard let selfLink = jrd.links.first(where: {
            $0.rel == WebFingerService.selfRel &&
            $0.type == WebFingerService.activityPubMediaType
        }), let hrefString = selfLink.href, let actorURL = URL(string: hrefString) else {
            throw WebFingerError.noActivityPubLink
        }

        return actorURL
    }

    /// Fetches and decodes an `APActor` document from the given URL.
    ///
    /// Resolved actors are cached for `cacheTTL` seconds to avoid redundant requests.
    ///
    /// - Parameter url: The URL of the actor's ActivityPub document.
    /// - Returns: The decoded `APActor`.
    /// - Throws: `WebFingerError.networkError` or a `DecodingError`.
    public func fetchActor(url: URL) async throws -> APActor {
        let cacheKey = url.absoluteString as NSString

        // Return a valid cached entry if available.
        if let cached = cache.object(forKey: cacheKey) {
            if Date().timeIntervalSince(cached.cachedAt) < WebFingerService.cacheTTL {
                return cached.actor
            } else {
                cache.removeObject(forKey: cacheKey)
            }
        }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue(WebFingerService.activityPubMediaType, forHTTPHeaderField: "Accept")
        request.httpMethod = "GET"

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw WebFingerError.networkError(error)
        }

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw WebFingerError.notFound(url.absoluteString)
        }

        let actor = try decoder.decode(APActor.self, from: data)

        // Store in cache.
        cache.setObject(APActorWrapper(actor: actor), forKey: cacheKey)

        return actor
    }

    // MARK: - Private Helpers

    /// Builds the well-known WebFinger query URL.
    private func webFingerURL(host: String, resource: String) throws -> URL {
        var components        = URLComponents()
        components.scheme     = "https"
        components.host       = host
        components.path       = "/.well-known/webfinger"
        components.queryItems = [URLQueryItem(name: "resource", value: resource)]

        guard let url = components.url else {
            throw WebFingerError.invalidHandle(resource)
        }
        return url
    }

    /// Downloads and decodes a WebFinger JRD document.
    private func fetchWebFingerResource(at url: URL) async throws -> WebFingerResource {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("application/jrd+json", forHTTPHeaderField: "Accept")
        request.httpMethod = "GET"

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw WebFingerError.networkError(error)
        }

        if let http = response as? HTTPURLResponse {
            guard http.statusCode == 200 else {
                throw WebFingerError.notFound(url.absoluteString)
            }
        }

        return try decoder.decode(WebFingerResource.self, from: data)
    }

    // MARK: - Cache Management

    /// Manually removes a specific actor from the cache (e.g. after a profile update).
    public func evict(actorURL: URL) {
        cache.removeObject(forKey: actorURL.absoluteString as NSString)
    }

    /// Clears the entire in-memory actor cache.
    public func evictAll() {
        cache.removeAllObjects()
    }
}
