// Core/Mastodon/Models/JSONDecoder+Mastodon.swift
// Shared JSONDecoder configured for Mastodon/ActivityPub API responses.

import Foundation

extension JSONDecoder {
    static let mastodon: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
