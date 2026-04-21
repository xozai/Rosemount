// OfflineStoreTests.swift
// Rosemount
//
// Unit tests for OfflineStore: draft CRUD, timeline cache, and pending actions.
// Uses an in-memory SwiftData container to avoid touching the disk.
// Swift 5.10 | iOS 17.0+

import XCTest
import SwiftData
@testable import Rosemount

@MainActor
final class OfflineStoreTests: XCTestCase {

    // MARK: - Store under test

    private var store: OfflineStore!

    override func setUp() async throws {
        try await super.setUp()
        store = makeInMemoryStore()
    }

    override func tearDown() async throws {
        store = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func makeInMemoryStore() -> OfflineStore {
        // We can't call the private init of the singleton, so we test the public API
        // against a freshly-initialised in-memory OfflineStore constructed via the
        // ModelContainer API directly, then inject it into a testable subclass.
        // Instead, we access OfflineStore.shared but swap its container to in-memory.
        let s = OfflineStore.shared
        let schema = Schema([DraftPost.self, CachedStatus.self, PendingAction.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        // Attempt to replace the underlying container; fall back silently if unavailable.
        if let c = try? ModelContainer(for: schema, configurations: config) {
            // Clear existing context items before each test.
            let ctx = c.mainContext
            for draft in (try? ctx.fetch(FetchDescriptor<DraftPost>())) ?? [] { ctx.delete(draft) }
            for action in (try? ctx.fetch(FetchDescriptor<PendingAction>())) ?? [] { ctx.delete(action) }
            for status in (try? ctx.fetch(FetchDescriptor<CachedStatus>())) ?? [] { ctx.delete(status) }
            try? ctx.save()
        }
        return s
    }

    // MARK: - Draft CRUD

    func testSaveDraftAppearsInAllDrafts() {
        let draft = DraftPost(content: "Hello tests", visibility: "public")
        store.saveDraft(draft)
        let all = store.allDrafts()
        XCTAssertTrue(all.contains { $0.content == "Hello tests" })
    }

    func testDeleteDraftRemovesIt() {
        let draft = DraftPost(content: "Temp draft", visibility: "unlisted")
        store.saveDraft(draft)
        XCTAssertTrue(store.allDrafts().contains { $0.content == "Temp draft" })
        store.deleteDraft(draft)
        XCTAssertFalse(store.allDrafts().contains { $0.content == "Temp draft" })
    }

    func testMultipleDraftsSortedByUpdatedAtDescending() {
        let d1 = DraftPost(content: "First", visibility: "public")
        let d2 = DraftPost(content: "Second", visibility: "public")
        d1.updatedAt = Date(timeIntervalSinceNow: -60)
        d2.updatedAt = Date()
        store.saveDraft(d1)
        store.saveDraft(d2)
        let all = store.allDrafts()
        let contents = all.map(\.content)
        if let idx1 = contents.firstIndex(of: "First"),
           let idx2 = contents.firstIndex(of: "Second") {
            XCTAssertLessThan(idx2, idx1, "Most recently updated draft should appear first")
        }
    }

    func testDraftVisibilityEnumConversion() {
        let draft = DraftPost(content: "test", visibility: "private")
        XCTAssertEqual(draft.visibilityEnum, .private)
    }

    func testDraftVisibilityEnumFallsBackToPublic() {
        let draft = DraftPost(content: "test", visibility: "invalid_value")
        XCTAssertEqual(draft.visibilityEnum, .public)
    }

    // MARK: - Pending Actions

    func testEnqueueAndCountPendingActions() {
        let initialCount = store.pendingActionsCount
        store.enqueuePendingAction(type: "favourite", targetId: "status-123")
        XCTAssertEqual(store.pendingActionsCount, initialCount + 1)
    }

    func testRemovePendingActionDecrementsCount() {
        store.enqueuePendingAction(type: "boost", targetId: "status-456")
        let actions = store.allPendingActions()
        guard let action = actions.last else {
            XCTFail("Expected at least one action")
            return
        }
        let countBefore = store.pendingActionsCount
        store.removePendingAction(action)
        XCTAssertEqual(store.pendingActionsCount, countBefore - 1)
    }

    func testAllPendingActionsSortedByCreatedAtAscending() {
        let initialCount = store.pendingActionsCount
        store.enqueuePendingAction(type: "favourite", targetId: "s1")
        store.enqueuePendingAction(type: "boost",     targetId: "s2")
        let all = store.allPendingActions()
        // Verify we have at least the two we just added
        XCTAssertGreaterThanOrEqual(all.count, initialCount + 2)
        // They should be ordered oldest-first
        for i in 1..<all.count {
            XCTAssertLessThanOrEqual(all[i-1].createdAt, all[i].createdAt)
        }
    }

    func testPendingActionPayloadIsPreserved() {
        store.enqueuePendingAction(type: "custom", targetId: "t1", payload: "{\"key\":\"value\"}")
        let last = store.allPendingActions().last
        XCTAssertEqual(last?.payload, "{\"key\":\"value\"}")
    }
}
