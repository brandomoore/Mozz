import Foundation
import GRDB
import MozzCore
@testable import MozzDatabase
import XCTest

/// A mix belongs to the server whose listening built it.
///
/// Mixes were stored globally, so an installation signed in to two servers
/// showed one server's mixes on the other's Home — drawn from artwork keys the
/// other server has never heard of, which rendered as blank tiles. Nothing was
/// wrong while only one server could be signed in to at a time, which is why it
/// sat there until the phones learned to hold several.
final class MixServerScopeTests: XCTestCase {
    private func library(
        _ database: MusicDatabase,
        serverId: String,
        tracks: ClosedRange<Int>
    ) async throws {
        let writer = CatalogWriter(database)
        try await writer.saveServer(ServerConnection(
            id: serverId, kind: .jellyfin, name: serverId,
            baseURL: URL(string: "https://\(serverId).example.test")!,
            userID: nil, clientIdentifier: "c"))
        try await writer.upsertTracks(tracks.map {
            Track(id: "t\($0)", title: "Track \($0)",
                  artistName: "Artist", artistID: "a", duration: 180)
        }, serverId: serverId)
    }

    private func mix(
        _ store: RecommendationStore,
        id: String,
        serverId: String,
        kind: String = "supermix",
        trackIds: [Int]
    ) async throws {
        try await store.saveRecommendationSet(
            RecommendationSetRecord(id: id, title: id, kind: kind, serverId: serverId),
            items: trackIds.enumerated().map { index, track in
                RecommendationItemRecord(
                    setId: id, trackRef: "\(serverId):t\(track)",
                    rank: index + 1, score: 1, inLibrary: true, reason: nil)
            })
    }

    /// Home asks for one server's mixes and gets one server's mixes.
    func testOnlyTheServerBeingBrowsedContributesItsMixes() async throws {
        let database = try MusicDatabase.inMemory()
        try await library(database, serverId: "srv-a", tracks: 1...4)
        try await library(database, serverId: "srv-b", tracks: 5...8)
        let store = RecommendationStore(database)

        try await mix(store, id: "supermix@srv-a", serverId: "srv-a", trackIds: [1, 2])
        try await mix(store, id: "supermix@srv-b", serverId: "srv-b", trackIds: [5, 6])

        let a = try await store.allSets(serverId: "srv-a")
        let b = try await store.allSets(serverId: "srv-b")

        XCTAssertEqual(a.map(\.id), ["supermix@srv-a"])
        XCTAssertEqual(b.map(\.id), ["supermix@srv-b"])
    }

    /// Regenerating one server's mixes must not throw away another's. The
    /// delete-before-regenerate is what would have done it.
    func testRegeneratingOneServersMixesLeavesTheOthersAlone() async throws {
        let database = try MusicDatabase.inMemory()
        try await library(database, serverId: "srv-a", tracks: 1...4)
        try await library(database, serverId: "srv-b", tracks: 5...8)
        let store = RecommendationStore(database)

        try await mix(store, id: "supermix@srv-a", serverId: "srv-a", trackIds: [1, 2])
        try await mix(store, id: "supermix@srv-b", serverId: "srv-b", trackIds: [5, 6])

        try await store.deleteSets(kinds: ["supermix"], serverId: "srv-a")

        let a = try await store.allSets(serverId: "srv-a")
        let b = try await store.allSets(serverId: "srv-b")
        XCTAssertTrue(a.isEmpty)
        XCTAssertEqual(b.map(\.id), ["supermix@srv-b"])
    }

    /// Two servers each keep their own "latest of this kind".
    func testTheLatestSetOfAKindIsPerServer() async throws {
        let database = try MusicDatabase.inMemory()
        try await library(database, serverId: "srv-a", tracks: 1...4)
        try await library(database, serverId: "srv-b", tracks: 5...8)
        let store = RecommendationStore(database)

        try await mix(store, id: "mozz-weekly@srv-a", serverId: "srv-a",
                      kind: "forgotten", trackIds: [1])
        try await mix(store, id: "mozz-weekly@srv-b", serverId: "srv-b",
                      kind: "forgotten", trackIds: [5])

        let a = try await store.latestSet(kind: "forgotten", serverId: "srv-a")
        XCTAssertEqual(a?.id, "mozz-weekly@srv-a")
        let b = try await store.latestSet(kind: "forgotten", serverId: "srv-b")
        XCTAssertEqual(b?.id, "mozz-weekly@srv-b")
    }

    /// The migration places mixes that were written before the column existed.
    ///
    /// This is the part that runs against a real library, so it is tested
    /// against a row written the old way: no `server_id`, and its items keyed on
    /// `serverId:remoteId` — which is what makes the backfill exact rather than
    /// a guess. A set whose tracks are gone cannot be placed under any server
    /// and is deleted; mixes are derived and regenerate.
    func testTheMigrationFilesOldMixesUnderTheRightServer() async throws {
        let database = try MusicDatabase.inMemory()
        try await library(database, serverId: "srv-a", tracks: 1...4)
        try await library(database, serverId: "srv-b", tracks: 5...8)

        try await database.write { db in
            // Written the old way: the column exists by now, so null it out to
            // stand in for a row that predates it.
            for (id, serverId, track) in [
                ("supermix", "srv-a", 1),
                ("daily-mix-1", "srv-b", 5),
            ] {
                try db.execute(sql: """
                    INSERT INTO recommendation_set (id, title, kind, generated_at, server_id)
                    VALUES (?, ?, 'supermix', 1, NULL)
                    """, arguments: [id, id])
                try db.execute(sql: """
                    INSERT INTO recommendation_item
                        (set_id, track_ref, rank, score, in_library)
                    VALUES (?, ?, 1, 1, 1)
                    """, arguments: [id, "\(serverId):t\(track)"])
            }
            // And one whose tracks no longer exist anywhere.
            try db.execute(sql: """
                INSERT INTO recommendation_set (id, title, kind, generated_at, server_id)
                VALUES ('orphan', 'Orphan', 'supermix', 1, NULL)
                """)
            try db.execute(sql: """
                INSERT INTO recommendation_item (set_id, track_ref, rank, score, in_library)
                VALUES ('orphan', 'srv-gone:t99', 1, 1, 1)
                """)
        }

        try await database.write { db in
            try Schema.backfillMixServerIds(db)
        }

        let store = RecommendationStore(database)
        // Placed, and renamed to the id a fresh generation would write — so the
        // next regeneration replaces these rows rather than doubling them.
        let placedA = try await store.allSets(serverId: "srv-a")
        let placedB = try await store.allSets(serverId: "srv-b")
        XCTAssertEqual(placedA.map(\.id), ["supermix@srv-a"])
        XCTAssertEqual(placedB.map(\.id), ["daily-mix-1@srv-b"])

        // Their items moved with them: the foreign key does not cascade updates.
        let items = try await store.items(forSet: "supermix@srv-a")
        XCTAssertEqual(items.map(\.trackRef), ["srv-a:t1"])

        // The unplaceable one is gone, items and all.
        let orphans = try await database.read { db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM recommendation_item WHERE set_id = 'orphan'
                """) ?? -1
        }
        XCTAssertEqual(orphans, 0)
        let orphanSet = try await store.set(id: "orphan")
        XCTAssertNil(orphanSet)
    }
}
