// APCollection.swift
// Rosemount
//
// ActivityPub OrderedCollection and Collection types, including paged collection support.
// Items within a collection may arrive as full Activity objects or as plain URL strings;
// the custom Codable implementations handle both cases transparently.

import Foundation

// MARK: - APCollectionType

/// Differentiates between ordered and unordered ActivityPub collections.
public enum APCollectionType: String, Codable, Sendable {
    case orderedCollection     = "OrderedCollection"
    case collection            = "Collection"
    case orderedCollectionPage = "OrderedCollectionPage"
    case collectionPage        = "CollectionPage"
}

// MARK: - APCollectionItem

/// A single item inside a collection.
///
/// Items may be delivered as plain URL strings (compacted IRIs) or as fully-embedded
/// `APActivity` objects.  Custom `Codable` resolves the ambiguity at decode time.
public enum APCollectionItem: Sendable, Equatable {
    case string(String)
    case activity(APActivity)
}

extension APCollectionItem: Codable {

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        // Try a plain string first — this is the compact IRI / ID-only form.
        if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
            return
        }

        // Fall back to a full activity object.
        let activity = try container.decode(APActivity.self)
        self = .activity(activity)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s):    try container.encode(s)
        case .activity(let a):  try container.encode(a)
        }
    }

    // MARK: Convenience

    /// The URL string for this item — the string value directly, or the activity's `id`.
    public var id: String? {
        switch self {
        case .string(let s):    return s
        case .activity(let a):  return a.id
        }
    }
}

// MARK: - APCollectionFirstPage

/// The `first` property of an `APCollection`.
///
/// It may be either a plain URL string pointing to the first page, or an inline
/// `APCollectionPage` object embedded directly within the collection document.
public enum APCollectionFirstPage: Sendable, Equatable {
    case url(String)
    case page(APCollectionPage)
}

extension APCollectionFirstPage: Codable {

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let urlString = try? container.decode(String.self) {
            self = .url(urlString)
            return
        }
        let page = try container.decode(APCollectionPage.self)
        self = .page(page)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .url(let s):     try container.encode(s)
        case .page(let p):    try container.encode(p)
        }
    }

    /// Returns the URL string regardless of which case is active.
    public var urlString: String? {
        switch self {
        case .url(let s):  return s
        case .page(let p): return p.id
        }
    }
}

// MARK: - APCollection

/// An ActivityPub `OrderedCollection` or `Collection` document.
///
/// Collections are used for an actor's outbox, followers list, following list, etc.
/// The `first` field may be an inline page or a URL to the first page of results.
/// The `items`/`orderedItems` arrays, when present, may contain full objects or URL strings.
public struct APCollection: Sendable, Equatable {

    // MARK: JSON-LD

    /// JSON-LD context, normalised to a string.
    public let context: String?

    // MARK: Core

    /// The canonical URL of this collection.
    public let id: String?
    /// The collection type.
    public let type: APCollectionType
    /// Total number of items in the collection (across all pages).
    public let totalItems: Int?

    // MARK: Pagination

    /// The first page of this collection (URL string or inline page object).
    public let first: APCollectionFirstPage?
    /// URL of the last page, if provided.
    public let last: String?

    // MARK: Inline items

    /// Inline items for single-page or compact collections (unordered).
    public let items: [APCollectionItem]?
    /// Inline items for single-page ordered collections.
    public let orderedItems: [APCollectionItem]?

    // MARK: - Convenience

    /// All items regardless of whether they were in `items` or `orderedItems`.
    public var allItems: [APCollectionItem] {
        orderedItems ?? items ?? []
    }

    // MARK: - Memberwise init

    public init(
        context: String? = "https://www.w3.org/ns/activitystreams",
        id: String? = nil,
        type: APCollectionType = .orderedCollection,
        totalItems: Int? = nil,
        first: APCollectionFirstPage? = nil,
        last: String? = nil,
        items: [APCollectionItem]? = nil,
        orderedItems: [APCollectionItem]? = nil
    ) {
        self.context = context
        self.id = id
        self.type = type
        self.totalItems = totalItems
        self.first = first
        self.last = last
        self.items = items
        self.orderedItems = orderedItems
    }
}

// MARK: - APCollection + Codable

extension APCollection: Codable {

    public enum CodingKeys: String, CodingKey {
        case context      = "@context"
        case id
        case type
        case totalItems
        case first
        case last
        case items
        case orderedItems
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // @context — same string/array normalisation as APActor.
        if let s = try? container.decode(String.self, forKey: .context) {
            context = s
        } else if (try? container.nestedUnkeyedContainer(forKey: .context)) != nil {
            context = "https://www.w3.org/ns/activitystreams"
        } else {
            context = nil
        }

        id           = try container.decodeIfPresent(String.self,                 forKey: .id)
        type         = try container.decode(APCollectionType.self,                forKey: .type)
        totalItems   = try container.decodeIfPresent(Int.self,                    forKey: .totalItems)
        first        = try container.decodeIfPresent(APCollectionFirstPage.self,  forKey: .first)
        last         = try container.decodeIfPresent(String.self,                 forKey: .last)
        items        = try container.decodeIfPresent([APCollectionItem].self,     forKey: .items)
        orderedItems = try container.decodeIfPresent([APCollectionItem].self,     forKey: .orderedItems)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(context,      forKey: .context)
        try container.encodeIfPresent(id,           forKey: .id)
        try container.encode(type,                  forKey: .type)
        try container.encodeIfPresent(totalItems,   forKey: .totalItems)
        try container.encodeIfPresent(first,        forKey: .first)
        try container.encodeIfPresent(last,         forKey: .last)
        try container.encodeIfPresent(items,        forKey: .items)
        try container.encodeIfPresent(orderedItems, forKey: .orderedItems)
    }
}

// MARK: - APCollectionPage

/// A single page within an `APCollection`, supporting both ordered and unordered variants.
///
/// Paged collections are used when the server wants to paginate large sets of items.
/// Each page carries its own `next` / `prev` links and the slice of items for that page.
public struct APCollectionPage: Sendable, Equatable {

    // MARK: Core

    /// The canonical URL of this page.
    public let id: String?
    /// The page type (`OrderedCollectionPage` or `CollectionPage`).
    public let type: APCollectionType?
    /// URL of the parent collection this page belongs to.
    public let partOf: String?

    // MARK: Pagination links

    /// URL of the next page, if any.
    public let next: String?
    /// URL of the previous page, if any.
    public let prev: String?

    // MARK: Items

    /// Ordered items on this page (for `OrderedCollectionPage`).
    public let orderedItems: [APCollectionItem]?
    /// Unordered items on this page (for `CollectionPage`).
    public let items: [APCollectionItem]?

    // MARK: - Convenience

    /// All items on this page regardless of ordering variant.
    public var allItems: [APCollectionItem] {
        orderedItems ?? items ?? []
    }

    // MARK: - Memberwise init

    public init(
        id: String? = nil,
        type: APCollectionType? = .orderedCollectionPage,
        partOf: String? = nil,
        next: String? = nil,
        prev: String? = nil,
        orderedItems: [APCollectionItem]? = nil,
        items: [APCollectionItem]? = nil
    ) {
        self.id = id
        self.type = type
        self.partOf = partOf
        self.next = next
        self.prev = prev
        self.orderedItems = orderedItems
        self.items = items
    }
}

// MARK: - APCollectionPage + Codable

extension APCollectionPage: Codable {

    public enum CodingKeys: String, CodingKey {
        case id
        case type
        case partOf
        case next
        case prev
        case orderedItems
        case items
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id           = try container.decodeIfPresent(String.self,             forKey: .id)
        type         = try container.decodeIfPresent(APCollectionType.self,   forKey: .type)
        partOf       = try container.decodeIfPresent(String.self,             forKey: .partOf)
        next         = try container.decodeIfPresent(String.self,             forKey: .next)
        prev         = try container.decodeIfPresent(String.self,             forKey: .prev)
        orderedItems = try container.decodeIfPresent([APCollectionItem].self, forKey: .orderedItems)
        items        = try container.decodeIfPresent([APCollectionItem].self, forKey: .items)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id,           forKey: .id)
        try container.encodeIfPresent(type,         forKey: .type)
        try container.encodeIfPresent(partOf,       forKey: .partOf)
        try container.encodeIfPresent(next,         forKey: .next)
        try container.encodeIfPresent(prev,         forKey: .prev)
        try container.encodeIfPresent(orderedItems, forKey: .orderedItems)
        try container.encodeIfPresent(items,        forKey: .items)
    }
}
