import Foundation
import GRDB
@testable import MozzDatabase
import XCTest

/// Runs the migrations against a copy of a real library, when one is pointed at.
///
/// Skipped unless `MOZZ_PROBE_DB` names a database file, so it is inert in CI
/// and on anyone else's machine. It exists because a migration gets one attempt
/// on a machine that matters, and a fixture cannot tell you what a real
/// catalogue — with its half-synced servers, its orphaned rows and its years of
/// accumulated history — will do to it. Copy the library first; this writes.
///
///     MOZZ_PROBE_DB=/tmp/copy.sqlite swift test --filter RealLibraryMigrationProbe
final class RealLibraryMigrationProbe: XCTestCase {
    func testEveryMixLandsUnderAServer() async throws {
        guard let path = ProcessInfo.processInfo.environment["MOZZ_PROBE_DB"] else {
            throw XCTSkip("MOZZ_PROBE_DB not set")
        }
        // Opening runs the migrations.
        let database = try MusicDatabase.open(at: URL(fileURLWithPath: path))

        let rows = try await database.read { db in
            try Row.fetchAll(db, sql: "SELECT id, kind, server_id FROM recommendation_set")
                .map { (id: $0["id"] as String, kind: $0["kind"] as String,
                        serverId: $0["server_id"] as String?) }
        }
        print("probe: \(rows.count) mixes")
        for row in rows { print("  \(row.id) kind=\(row.kind) server=\(row.serverId ?? "nil")") }

        // Nothing may be left unplaceable: the migration either files a mix
        // under its server or deletes it.
        XCTAssertTrue(rows.allSatisfy { $0.serverId != nil })
        // And every row carries the id a fresh generation would write, or the
        // next one doubles the tile instead of replacing it.
        XCTAssertTrue(rows.allSatisfy { $0.id.hasSuffix("@\($0.serverId ?? "")") })

        // Every one of them is reachable through the scoped read Home uses.
        let store = RecommendationStore(database)
        for serverId in Set(rows.compactMap(\.serverId)) {
            let sets = try await store.allSets(serverId: serverId)
            XCTAssertEqual(sets.count, rows.filter { $0.serverId == serverId }.count)
        }
    }
}
