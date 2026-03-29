// ActivityPubClient.swift
// Rosemount
//
// ActivityPub HTTP client for delivering activities to remote actor inboxes
// and fetching remote ActivityPub resources (actors, collections, outboxes).
//
// Outbound requests are HTTP-signed using the actor's private key via
// HTTPSignatureService.  All I/O uses async/await on a URLSession with an
// ephemeral configuration so no cookies or credential storage are used.
//
// Retry policy: up to 2 retries on 5xx responses, with a 1-second delay
// between attempts.

import Foundation
import Security

// MARK: - AuthManagerProtocol

/// Minimal protocol for retrieving an actor's private signing key.
///
/// Conform your app's `AuthManager` (or a test double) to this protocol and
/// inject it into `ActivityPubClient` to keep the client independently testable.
public protocol AuthManagerProtocol: Sendable {
    /// Returns the RSA private `SecKey` for the given actor, or `nil` if unavailable.
    func privateKey(for actorId: String) async throws -> SecKey?
}

// MARK: - ActivityPubClientError

/// Errors thrown by `ActivityPubClient`.
public enum ActivityPubClientError: Error, Sendable, LocalizedError {
    /// A URL could not be constructed or was structurally invalid.
    case invalidURL(String)
    /// The server returned a non-2xx status code.
    case httpError(statusCode: Int, body: String?)
    /// The response body could not be decoded into the expected type.
    case decodingFailed(Error)
    /// The request could not be signed (wraps `HTTPSignatureError`).
    case signingFailed(Error)
    /// No private key is available for the local actor.
    case noPrivateKey

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .httpError(let code, let body):
            return "HTTP \(code)\(body.map { ": \($0)" } ?? "")"
        case .decodingFailed(let err):
            return "Decoding failed: \(err.localizedDescription)"
        case .signingFailed(let err):
            return "HTTP Signature signing failed: \(err.localizedDescription)"
        case .noPrivateKey:
            return "No private key available for the local actor."
        }
    }
}

// MARK: - ActivityPubClient

/// An actor that handles all outbound ActivityPub HTTP traffic.
///
/// Responsibilities:
/// - Serialise `APActivity` values to JSON and POST them to remote inboxes.
/// - Fetch remote `APActor`, `APCollection`, and `APCollectionPage` documents.
/// - Sign all requests using `HTTPSignatureService`.
/// - Retry automatically on transient server errors (5xx), up to `maxRetries` attempts.
///
/// Usage:
/// ```swift
/// let client = ActivityPubClient(authManager: myAuthManager)
/// try await client.deliver(activity: followActivity, to: inboxURL, as: localActor)
/// ```
public actor ActivityPubClient {

    // MARK: - Constants

    private static let activityPubMediaType = "application/activity+json"
    private static let maxRetries           = 2
    private static let retryDelay: UInt64   = 1_000_000_000   // 1 second in nanoseconds

    // MARK: - Dependencies

    private let urlSession:   URLSession
    private let signer:       HTTPSignatureService
    private let authManager:  any AuthManagerProtocol
    private let encoder:      JSONEncoder
    private let decoder:      JSONDecoder

    // MARK: - Init

    /// Creates a new `ActivityPubClient`.
    ///
    /// - Parameters:
    ///   - authManager: Provides the local actor's private signing key.
    ///   - signer:      The HTTP Signature service (defaults to a new instance).
    ///   - urlSession:  The URL session to use (defaults to `.ephemeral`).
    public init(
        authManager: some AuthManagerProtocol,
        signer: HTTPSignatureService = HTTPSignatureService(),
        urlSession: URLSession = .init(configuration: .ephemeral)
    ) {
        self.authManager = authManager
        self.signer      = signer
        self.urlSession  = urlSession

        let enc                       = JSONEncoder()
        enc.outputFormatting          = [.sortedKeys]
        enc.dateEncodingStrategy      = .iso8601
        self.encoder                  = enc

        let dec                       = JSONDecoder()
        dec.dateDecodingStrategy      = .iso8601
        self.decoder                  = dec
    }

    // MARK: - Public API

    /// Serialises and delivers an `APActivity` to a remote actor's inbox.
    ///
    /// The request body is the JSON-encoded activity.  A `Digest` header is added
    /// over the body, and the full request is signed with the local actor's private key.
    ///
    /// - Parameters:
    ///   - activity:  The activity to deliver.
    ///   - inboxURL:  The remote inbox URL.
    ///   - actor:     The local actor performing the activity (provides key ID).
    /// - Throws: `ActivityPubClientError` on network, signing, or HTTP errors.
    public func deliver(
        activity: APActivity,
        to inboxURL: URL,
        as actor: APActor
    ) async throws {
        let body: Data
        do {
            body = try encoder.encode(activity)
        } catch {
            throw ActivityPubClientError.decodingFailed(error)
        }

        var request = URLRequest(url: inboxURL, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = "POST"
        request.httpBody   = body
        request.setValue(Self.activityPubMediaType, forHTTPHeaderField: "Content-Type")
        request.setValue(Self.activityPubMediaType, forHTTPHeaderField: "Accept")
        request.setValue(String(body.count),        forHTTPHeaderField: "Content-Length")

        // Retrieve the actor's private key.
        guard let privateKey = try await authManager.privateKey(for: actor.id) else {
            throw ActivityPubClientError.noPrivateKey
        }

        // Sign the request.
        let keyId = actor.publicKey?.id ?? "\(actor.id)#main-key"
        do {
            try await signer.sign(request: &request, keyId: keyId, privateKey: privateKey)
        } catch {
            throw ActivityPubClientError.signingFailed(error)
        }

        try await performRequest(request, expectingStatus: 200...202)
    }

    /// Fetches and decodes an `APActor` document from a remote URL.
    ///
    /// - Parameter url: The actor document URL.
    /// - Returns: The decoded `APActor`.
    /// - Throws: `ActivityPubClientError` on network or decoding failure.
    public func fetchActor(at url: URL) async throws -> APActor {
        let data = try await fetchData(from: url)
        do {
            return try decoder.decode(APActor.self, from: data)
        } catch {
            throw ActivityPubClientError.decodingFailed(error)
        }
    }

    /// Fetches and decodes an `APCollection` document from a remote URL.
    ///
    /// - Parameter url: The collection URL (e.g. an actor's outbox or followers URL).
    /// - Returns: The decoded `APCollection`.
    /// - Throws: `ActivityPubClientError` on network or decoding failure.
    public func fetchCollection(at url: URL) async throws -> APCollection {
        let data = try await fetchData(from: url)
        do {
            return try decoder.decode(APCollection.self, from: data)
        } catch {
            throw ActivityPubClientError.decodingFailed(error)
        }
    }

    /// Fetches the first page of a remote actor's outbox.
    ///
    /// If the outbox collection's `first` property is an inline page it is returned
    /// directly; otherwise the URL is followed to fetch the page separately.
    ///
    /// - Parameter actorURL: The URL of the remote actor.
    /// - Returns: The first `APCollectionPage` of the actor's outbox.
    /// - Throws: `ActivityPubClientError` on network or decoding failure.
    public func fetchOutbox(for actorURL: URL) async throws -> APCollectionPage {
        let actor      = try await fetchActor(at: actorURL)
        let outboxURLString = actor.outbox
        guard let outboxURL = URL(string: outboxURLString) else {
            throw ActivityPubClientError.invalidURL(outboxURLString)
        }

        let collection = try await fetchCollection(at: outboxURL)

        switch collection.first {
        case .page(let inlinePage):
            return inlinePage

        case .url(let pageURLString):
            guard let pageURL = URL(string: pageURLString) else {
                throw ActivityPubClientError.invalidURL(pageURLString)
            }
            return try await fetchCollectionPage(at: pageURL)

        case nil:
            // Return a synthetic empty page when the collection has no first link.
            return APCollectionPage(
                id: collection.id,
                type: .orderedCollectionPage,
                partOf: collection.id,
                orderedItems: collection.orderedItems ?? []
            )
        }
    }

    // MARK: - Private: Collection Page

    /// Fetches and decodes an `APCollectionPage` document.
    private func fetchCollectionPage(at url: URL) async throws -> APCollectionPage {
        let data = try await fetchData(from: url)
        do {
            return try decoder.decode(APCollectionPage.self, from: data)
        } catch {
            throw ActivityPubClientError.decodingFailed(error)
        }
    }

    // MARK: - Private: HTTP Helpers

    /// Builds and executes a GET request for an ActivityPub document, returning raw `Data`.
    private func fetchData(from url: URL) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = "GET"
        request.setValue(Self.activityPubMediaType, forHTTPHeaderField: "Accept")

        return try await performRequest(request, expectingStatus: 200...200)
    }

    /// Executes a `URLRequest` with retry logic on 5xx responses.
    ///
    /// - Parameters:
    ///   - request:         The request to execute.
    ///   - expectingStatus: The range of acceptable HTTP status codes.
    /// - Returns: The response body `Data` (empty `Data` if the response has no body).
    /// - Throws: `ActivityPubClientError.httpError` after all retries are exhausted.
    @discardableResult
    private func performRequest(
        _ request: URLRequest,
        expectingStatus statusRange: ClosedRange<Int>
    ) async throws -> Data {
        var lastError: Error?
        var attempt = 0

        while attempt <= Self.maxRetries {
            if attempt > 0 {
                try await Task.sleep(nanoseconds: Self.retryDelay)
            }

            do {
                let (data, response) = try await urlSession.data(for: request)

                guard let http = response as? HTTPURLResponse else {
                    // Non-HTTP response — treat as a generic network error.
                    throw ActivityPubClientError.httpError(statusCode: -1, body: nil)
                }

                if statusRange.contains(http.statusCode) {
                    return data
                }

                // Server error (5xx) — eligible for retry.
                if (500...599).contains(http.statusCode) {
                    let bodyString = String(data: data, encoding: .utf8)
                    lastError = ActivityPubClientError.httpError(
                        statusCode: http.statusCode,
                        body: bodyString
                    )
                    attempt += 1
                    continue
                }

                // Client error (4xx) or unexpected redirect — fail immediately.
                let bodyString = String(data: data, encoding: .utf8)
                throw ActivityPubClientError.httpError(
                    statusCode: http.statusCode,
                    body: bodyString
                )

            } catch let clientError as ActivityPubClientError {
                throw clientError
            } catch {
                // Network-level errors (no connectivity, timeout, etc.) — retry.
                lastError = ActivityPubClientError.httpError(statusCode: -1, body: error.localizedDescription)
                attempt += 1
            }
        }

        // All retry attempts exhausted.
        throw lastError ?? ActivityPubClientError.httpError(statusCode: -1, body: "Max retries exceeded")
    }
}
