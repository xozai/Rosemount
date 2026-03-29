// HTTPSignature.swift
// Rosemount
//
// HTTP Signature generation and verification for ActivityPub federation.
//
// Implements draft-cavage-http-signatures (as used by Mastodon and other AP implementations).
// Signing covers: (request-target), host, date, digest (SHA-256 of body).
//
// RSA operations use the Security framework (SecKey APIs) — CryptoKit handles SHA-256
// digests.  No third-party dependencies.

import Foundation
import CryptoKit
import Security

// MARK: - HTTPSignatureError

/// Errors thrown by `HTTPSignatureService` and the key-management helpers.
public enum HTTPSignatureError: Error, Sendable, LocalizedError {
    /// A required HTTP header was absent from the request.
    case missingHeader(String)
    /// The PEM string could not be parsed into a valid RSA key.
    case invalidKeyFormat(String)
    /// The signing operation failed, with the underlying `OSStatus` or message attached.
    case signatureFailed(String)
    /// The signature did not match the reconstructed signing string.
    case verificationFailed
    /// The Signature header had an unexpected or malformed format.
    case malformedSignatureHeader

    public var errorDescription: String? {
        switch self {
        case .missingHeader(let h):         return "Required HTTP header missing: '\(h)'"
        case .invalidKeyFormat(let detail): return "Invalid RSA key format: \(detail)"
        case .signatureFailed(let detail):  return "HTTP Signature signing failed: \(detail)"
        case .verificationFailed:           return "HTTP Signature verification failed — signature mismatch."
        case .malformedSignatureHeader:     return "The Signature header is malformed or missing required parameters."
        }
    }
}

// MARK: - HTTPSignatureService

/// An actor that signs outgoing `URLRequest`s and verifies incoming HTTP Signatures.
///
/// Signing algorithm: `rsa-sha256`
/// Signed headers: `(request-target)`, `host`, `date`, `digest`
///
/// > Important: All operations are isolated to this actor, ensuring thread-safety for
/// > any mutable state (e.g. a nonce cache or statistics counters you may add later).
public actor HTTPSignatureService {

    // MARK: - Constants

    private static let signatureAlgorithm = "rsa-sha256"
    private static let signedHeaders      = "(request-target) host date digest"

    // MARK: - Init

    public init() {}

    // MARK: - Public API: Signing

    /// Signs the given `URLRequest` by adding `Date`, `Digest`, and `Signature` headers.
    ///
    /// The signing string covers `(request-target)`, `host`, `date`, and `digest`.
    ///
    /// - Parameters:
    ///   - request:    The request to sign (mutated in place via `inout`).
    ///   - keyId:      The `keyId` field of the Signature header (typically the actor's key URL).
    ///   - privateKey: The actor's RSA-2048 (or larger) private key as a `SecKey`.
    /// - Throws: `HTTPSignatureError` on failure.
    public func sign(request: inout URLRequest, keyId: String, privateKey: SecKey) throws {
        guard let url = request.url else {
            throw HTTPSignatureError.missingHeader("url")
        }

        // Ensure mandatory headers are present.
        guard let host = url.host else {
            throw HTTPSignatureError.missingHeader("host")
        }

        // Set Date header if not already present.
        let dateString: String
        if let existingDate = request.value(forHTTPHeaderField: "Date") {
            dateString = existingDate
        } else {
            dateString = HTTPDate.string(from: Date())
            request.setValue(dateString, forHTTPHeaderField: "Date")
        }

        // Build and set the Digest header (SHA-256 of the body).
        let body           = request.httpBody ?? Data()
        let digestString   = Self.digestHeader(for: body)
        request.setValue(digestString, forHTTPHeaderField: "Digest")

        // Determine the request-target pseudo-header value.
        let method         = (request.httpMethod ?? "post").lowercased()
        let pathAndQuery   = Self.pathAndQuery(from: url)
        let requestTarget  = "\(method) \(pathAndQuery)"

        // Build the signing string.
        let signingString  = Self.buildSigningString(
            requestTarget: requestTarget,
            host: host,
            date: dateString,
            digest: digestString
        )

        guard let signingData = signingString.data(using: .utf8) else {
            throw HTTPSignatureError.signatureFailed("Could not encode signing string as UTF-8.")
        }

        // Sign with RSA-SHA256.
        let signatureData = try Self.rsaSign(data: signingData, privateKey: privateKey)
        let signatureB64  = signatureData.base64EncodedString()

        // Compose and set the Signature header.
        let signatureHeader = """
        keyId="\(keyId)",algorithm="\(Self.signatureAlgorithm)",headers="\(Self.signedHeaders)",signature="\(signatureB64)"
        """
        request.setValue(signatureHeader, forHTTPHeaderField: "Signature")
    }

    // MARK: - Public API: Verification

    /// Verifies the `Signature` header on an incoming request against a known public key.
    ///
    /// - Parameters:
    ///   - request:      The incoming `URLRequest` carrying the `Signature` header.
    ///   - publicKeyPem: The PEM-encoded RSA public key of the signing actor.
    /// - Returns: `true` if the signature is valid.
    /// - Throws: `HTTPSignatureError` on missing headers, key parse errors, or invalid format.
    public func verify(request: URLRequest, publicKeyPem: String) throws -> Bool {
        // Parse the Signature header into its component parameters.
        guard let signatureHeader = request.value(forHTTPHeaderField: "Signature") else {
            throw HTTPSignatureError.missingHeader("Signature")
        }

        let params = Self.parseSignatureHeader(signatureHeader)
        guard let signatureB64 = params["signature"],
              let headersParam = params["headers"],
              let signatureData = Data(base64Encoded: signatureB64)
        else {
            throw HTTPSignatureError.malformedSignatureHeader
        }

        // Reconstruct the signing string from the headers listed in the `headers` param.
        let signingString = try Self.reconstructSigningString(
            from: request,
            headerNames: headersParam.split(separator: " ").map(String.init)
        )

        guard let signingData = signingString.data(using: .utf8) else {
            throw HTTPSignatureError.signatureFailed("Could not encode signing string as UTF-8.")
        }

        // Import the PEM key and verify.
        let publicKey = try HTTPSignatureService.importPublicKeyFromPEM(publicKeyPem)
        return try Self.rsaVerify(data: signingData, signature: signatureData, publicKey: publicKey)
    }

    // MARK: - Private: Signing String Helpers

    private static func buildSigningString(
        requestTarget: String,
        host: String,
        date: String,
        digest: String
    ) -> String {
        """
        (request-target): \(requestTarget)
        host: \(host)
        date: \(date)
        digest: \(digest)
        """
    }

    private static func reconstructSigningString(
        from request: URLRequest,
        headerNames: [String]
    ) throws -> String {
        var lines: [String] = []

        for name in headerNames {
            switch name.lowercased() {
            case "(request-target)":
                guard let url    = request.url,
                      let method = request.httpMethod else {
                    throw HTTPSignatureError.missingHeader("(request-target)")
                }
                let path = pathAndQuery(from: url)
                lines.append("(request-target): \(method.lowercased()) \(path)")

            default:
                guard let value = request.value(forHTTPHeaderField: name) else {
                    throw HTTPSignatureError.missingHeader(name)
                }
                lines.append("\(name.lowercased()): \(value)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func pathAndQuery(from url: URL) -> String {
        var result = url.path.isEmpty ? "/" : url.path
        if let query = url.query {
            result += "?\(query)"
        }
        return result
    }

    // MARK: - Private: Digest

    /// Computes the `SHA-256` digest of `data` and formats it as the `Digest` header value.
    static func digestHeader(for data: Data) -> String {
        let digest = SHA256.hash(data: data)
        let b64    = Data(digest).base64EncodedString()
        return "SHA-256=\(b64)"
    }

    // MARK: - Private: RSA Operations

    private static func rsaSign(data: Data, privateKey: SecKey) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            privateKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            data as CFData,
            &error
        ) as Data? else {
            let detail = error?.takeRetainedValue().localizedDescription ?? "unknown"
            throw HTTPSignatureError.signatureFailed(detail)
        }
        return signature
    }

    private static func rsaVerify(data: Data, signature: Data, publicKey: SecKey) throws -> Bool {
        var error: Unmanaged<CFError>?
        let valid = SecKeyVerifySignature(
            publicKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            data as CFData,
            signature as CFData,
            &error
        )
        if let cfError = error?.takeRetainedValue(), !valid {
            let code = CFErrorGetCode(cfError)
            // errSecVerifyFailed (-67808) means the signature is simply wrong — not a system error.
            if code == Int(errSecVerifyFailed) {
                return false
            }
            throw HTTPSignatureError.signatureFailed(cfError.localizedDescription)
        }
        return valid
    }

    // MARK: - Private: Signature Header Parsing

    /// Parses a `Signature` header value into a dictionary of parameter name → value.
    private static func parseSignatureHeader(_ header: String) -> [String: String] {
        // Format: key="value",key="value",...
        var result = [String: String]()
        let parts = header.components(separatedBy: ",")
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            guard let eqRange = trimmed.range(of: "=") else { continue }
            let key   = String(trimmed[trimmed.startIndex ..< eqRange.lowerBound])
            var value = String(trimmed[eqRange.upperBound...])
            // Strip surrounding quotes.
            if value.hasPrefix("\"") && value.hasSuffix("\"") {
                value = String(value.dropFirst().dropLast())
            }
            result[key] = value
        }
        return result
    }
}

// MARK: - Key Management Helpers

extension HTTPSignatureService {

    // MARK: Key Generation

    /// Generates a new RSA key pair suitable for ActivityPub HTTP Signatures.
    ///
    /// - Returns: A tuple of `(privateKey, publicKey)` as `SecKey` instances.
    /// - Throws: `HTTPSignatureError.signatureFailed` if the Security framework returns an error.
    public static func generateRSAKeyPair(
        bits: Int = 2048
    ) throws -> (privateKey: SecKey, publicKey: SecKey) {
        let attributes: [CFString: Any] = [
            kSecAttrKeyType:       kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits: bits
        ]

        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            let detail = error?.takeRetainedValue().localizedDescription ?? "unknown"
            throw HTTPSignatureError.signatureFailed("Key generation failed: \(detail)")
        }

        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw HTTPSignatureError.signatureFailed("Could not extract public key from generated private key.")
        }

        return (privateKey: privateKey, publicKey: publicKey)
    }

    // MARK: PEM Export

    /// Exports an RSA public key as a PEM-encoded string (`-----BEGIN PUBLIC KEY-----`).
    ///
    /// - Parameter key: The `SecKey` to export.
    /// - Returns: A PEM-formatted string.
    /// - Throws: `HTTPSignatureError.invalidKeyFormat` if the key cannot be serialised.
    public static func exportPublicKeyAsPEM(_ key: SecKey) throws -> String {
        var error: Unmanaged<CFError>?
        guard let keyData = SecKeyCopyExternalRepresentation(key, &error) as Data? else {
            let detail = error?.takeRetainedValue().localizedDescription ?? "unknown"
            throw HTTPSignatureError.invalidKeyFormat("Could not export key: \(detail)")
        }

        // SecKeyCopyExternalRepresentation for RSA public keys returns DER-encoded PKCS#1.
        // Most ActivityPub implementations expect SubjectPublicKeyInfo (SPKI) format.
        // We prepend the standard SPKI header for RSA-2048.
        let spkiData = Self.wrapInSPKI(pkcs1DER: keyData)
        let b64      = spkiData.base64EncodedString(options: [.lineLength64Characters])
        return "-----BEGIN PUBLIC KEY-----\n\(b64)\n-----END PUBLIC KEY-----"
    }

    // MARK: PEM Import

    /// Imports a PEM-encoded RSA public key into a `SecKey`.
    ///
    /// Accepts both `BEGIN PUBLIC KEY` (SPKI) and `BEGIN RSA PUBLIC KEY` (PKCS#1) headers.
    ///
    /// - Parameter pem: The PEM string.
    /// - Returns: A `SecKey` suitable for signature verification.
    /// - Throws: `HTTPSignatureError.invalidKeyFormat` on parse failure.
    public static func importPublicKeyFromPEM(_ pem: String) throws -> SecKey {
        let stripped = pem
            .components(separatedBy: .newlines)
            .filter { !$0.hasPrefix("-----") && !$0.isEmpty }
            .joined()

        guard let derData = Data(base64Encoded: stripped) else {
            throw HTTPSignatureError.invalidKeyFormat("Base64 decoding of PEM body failed.")
        }

        // Attempt to import as SPKI first, then fall back to PKCS#1.
        let keyData: Data
        if pem.contains("BEGIN PUBLIC KEY") {
            // Strip the SPKI header to get the PKCS#1 content the Security framework expects.
            keyData = Self.extractPKCS1FromSPKI(spkiDER: derData) ?? derData
        } else {
            keyData = derData
        }

        let attributes: [CFString: Any] = [
            kSecAttrKeyType:  kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPublic
        ]

        var error: Unmanaged<CFError>?
        guard let secKey = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, &error) else {
            let detail = error?.takeRetainedValue().localizedDescription ?? "unknown"
            throw HTTPSignatureError.invalidKeyFormat("SecKeyCreateWithData failed: \(detail)")
        }
        return secKey
    }

    // MARK: - SPKI / PKCS#1 DER Helpers

    /// Wraps a PKCS#1 RSA public key DER blob in an SPKI (`SubjectPublicKeyInfo`) DER wrapper.
    ///
    /// The SPKI structure is:
    /// ```
    /// SEQUENCE {
    ///   SEQUENCE {
    ///     OID rsaEncryption (1.2.840.113549.1.1.1)
    ///     NULL
    ///   }
    ///   BIT STRING { <pkcs1DER> }
    /// }
    /// ```
    private static func wrapInSPKI(pkcs1DER: Data) -> Data {
        // OID for rsaEncryption + NULL parameters.
        let oidBytes: [UInt8] = [
            0x30, 0x0d,                               // SEQUENCE (13 bytes)
              0x06, 0x09,                             //   OID (9 bytes)
                0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01,
              0x05, 0x00                              //   NULL
        ]

        // BIT STRING: 0x00 prefix byte (unused bits = 0) + DER key data.
        let bitStringContent = Data([0x00]) + pkcs1DER
        let bitStringEncoded = derEncodeTag(0x03, content: bitStringContent)

        let algorithmIdentifier = Data(oidBytes)
        let spkiContent         = algorithmIdentifier + bitStringEncoded
        return derEncodeTag(0x30, content: spkiContent)
    }

    /// Attempts to extract the raw PKCS#1 key bytes from an SPKI DER blob.
    /// Returns `nil` if the structure cannot be parsed (caller will use raw DER).
    private static func extractPKCS1FromSPKI(spkiDER: Data) -> Data? {
        // Skip over: SEQUENCE header, inner SEQUENCE (algorithmIdentifier), BIT STRING header + 0x00.
        // This is a best-effort extraction; failing gracefully is acceptable.
        var offset = 0
        let bytes  = [UInt8](spkiDER)

        // Outer SEQUENCE.
        guard parseDERTag(bytes: bytes, offset: &offset) == 0x30 else { return nil }
        _ = parseDERLength(bytes: bytes, offset: &offset)

        // Inner SEQUENCE (algorithmIdentifier) — skip it entirely.
        guard parseDERTag(bytes: bytes, offset: &offset) == 0x30 else { return nil }
        let innerLen = parseDERLength(bytes: bytes, offset: &offset)
        offset += innerLen

        // BIT STRING tag.
        guard parseDERTag(bytes: bytes, offset: &offset) == 0x03 else { return nil }
        let bitStringLen = parseDERLength(bytes: bytes, offset: &offset)
        // Skip the "unused bits" byte.
        offset += 1
        let contentLen = bitStringLen - 1
        guard offset + contentLen <= bytes.count else { return nil }
        return Data(bytes[offset ..< offset + contentLen])
    }

    // MARK: Minimal DER encoding / decoding utilities

    private static func derEncodeTag(_ tag: UInt8, content: Data) -> Data {
        var result = Data([tag])
        result.append(contentsOf: derEncodeLength(content.count))
        result.append(content)
        return result
    }

    private static func derEncodeLength(_ length: Int) -> [UInt8] {
        if length < 0x80 {
            return [UInt8(length)]
        } else if length <= 0xFF {
            return [0x81, UInt8(length)]
        } else {
            return [0x82, UInt8(length >> 8), UInt8(length & 0xFF)]
        }
    }

    private static func parseDERTag(bytes: [UInt8], offset: inout Int) -> UInt8? {
        guard offset < bytes.count else { return nil }
        defer { offset += 1 }
        return bytes[offset]
    }

    private static func parseDERLength(bytes: [UInt8], offset: inout Int) -> Int {
        guard offset < bytes.count else { return 0 }
        let first = Int(bytes[offset]); offset += 1
        if first < 0x80 { return first }
        let numBytes = first & 0x7F
        var length   = 0
        for _ in 0 ..< numBytes {
            guard offset < bytes.count else { return 0 }
            length = (length << 8) | Int(bytes[offset]); offset += 1
        }
        return length
    }
}

// MARK: - HTTPDate

/// Formats and parses HTTP-date strings as defined in RFC 7231 §7.1.1.1.
enum HTTPDate {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale     = Locale(identifier: "en_US_POSIX")
        f.timeZone   = TimeZone(identifier: "GMT")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return f
    }()

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }

    static func date(from string: String) -> Date? {
        formatter.date(from: string)
    }
}
