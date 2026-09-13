import Foundation
@testable import MozzApp
import MozzCore
import XCTest

/// Holding several servers at once, which is what the phone could not do.
///
/// The desktop has kept a list and switched between them for as long as it has
/// existed. iOS kept one session under one Keychain key, so signing in to a
/// second meant signing out of the first — and on Plex that means approving a
/// link again.
final class SessionPersistenceTests: XCTestCase {
    private func session(
        _ name: String,
        kind: BackendKind = .jellyfin,
        host: String? = nil,
        serverId: String? = nil
    ) -> StoredSession {
        // Server names have spaces in them and hosts do not; deriving one from
        // the other without this made the URL nil and every test crash at once.
        let derived = host ?? name.replacingOccurrences(of: " ", with: "-").lowercased()
        return StoredSession(
            kind: kind,
            baseURL: URL(string: "https://\(derived).example.test")!,
            token: "token-\(name)",
            userID: nil,
            serverName: name,
            clientIdentifier: "client",
            musicSectionID: nil,
            serverId: serverId)
    }

    /// An installation that has only ever had the single-session key reads as a
    /// list of one, without anything having to migrate it first.
    ///
    /// This is every phone in the field at the moment, and every device that has
    /// had a session arrive over iCloud Keychain from one. Getting it wrong
    /// signs people out.
    func testAnExistingSingleSessionReadsAsAListOfOne() throws {
        let store = InMemoryCredentialStore()
        let existing = session("Home Plex", kind: .plex)
        // Written the way the old build wrote it: the active key, nothing else.
        let data = try JSONEncoder().encode(existing)
        try store.setString(String(data: data, encoding: .utf8), forKey: SessionPersistence.key)

        let all = SessionPersistence.all(store)

        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.serverName, "Home Plex")
        XCTAssertEqual(SessionPersistence.load(store)?.token, "token-Home Plex")
    }

    /// The single key keeps being written, so a build without the list — or an
    /// older Mozz on the same iCloud account — still signs in rather than
    /// finding nothing and asking for a Plex link.
    func testTheActiveSessionIsStillWrittenWhereOlderBuildsLookForIt() {
        let store = InMemoryCredentialStore()
        SessionPersistence.save(session("Navidrome"), to: store)

        XCTAssertEqual(SessionPersistence.load(store)?.serverName, "Navidrome")
    }

    func testSavingASecondServerKeepsTheFirstAndMakesTheNewOneActive() {
        let store = InMemoryCredentialStore()
        SessionPersistence.save(session("Home Plex", kind: .plex), to: store)
        SessionPersistence.save(session("VPS Navidrome", kind: .subsonic), to: store)

        XCTAssertEqual(SessionPersistence.all(store).map(\.serverName), ["VPS Navidrome", "Home Plex"])
        XCTAssertEqual(SessionPersistence.load(store)?.serverName, "VPS Navidrome")
    }

    /// Re-saving the same server updates it in place rather than listing it
    /// twice — sessions are re-saved constantly, on every library choice and
    /// every Plex re-resolution.
    func testResavingAServerDoesNotDuplicateIt() {
        let store = InMemoryCredentialStore()
        SessionPersistence.save(session("Jelly", serverId: "srv-1"), to: store)
        SessionPersistence.save(session("Jelly Renamed", host: "jelly", serverId: "srv-1"), to: store)

        XCTAssertEqual(SessionPersistence.all(store).count, 1)
        XCTAssertEqual(SessionPersistence.all(store).first?.serverName, "Jelly Renamed")
    }

    /// An address that changes must not fork one server into two. Plex
    /// re-resolution does exactly this, which is why the identity is the frozen
    /// server id and not the URL. See ADR-0017.
    func testAServerThatMovesAddressStaysOneServer() {
        let store = InMemoryCredentialStore()
        SessionPersistence.save(session("Plex", host: "old-address", serverId: "srv-1"), to: store)
        SessionPersistence.save(session("Plex", host: "new-address", serverId: "srv-1"), to: store)

        XCTAssertEqual(SessionPersistence.all(store).count, 1)
        XCTAssertEqual(
            SessionPersistence.all(store).first?.baseURL.host,
            "new-address.example.test")
    }

    func testSwitchingMovesTheChosenServerToTheFrontAndKeepsTheRest() {
        let store = InMemoryCredentialStore()
        SessionPersistence.save(session("A", serverId: "a"), to: store)
        SessionPersistence.save(session("B", serverId: "b"), to: store)
        SessionPersistence.save(session("C", serverId: "c"), to: store)

        let chosen = SessionPersistence.activate("a", in: store)

        XCTAssertEqual(chosen?.serverName, "A")
        XCTAssertEqual(SessionPersistence.all(store).map(\.serverName), ["A", "C", "B"])
        XCTAssertEqual(SessionPersistence.load(store)?.serverName, "A")
    }

    /// Switching to something already signed out of is a stale tap, not a
    /// request to put it back.
    func testSwitchingToAServerThatIsGoneChangesNothing() {
        let store = InMemoryCredentialStore()
        SessionPersistence.save(session("A", serverId: "a"), to: store)

        XCTAssertNil(SessionPersistence.activate("gone", in: store))
        XCTAssertEqual(SessionPersistence.all(store).map(\.serverName), ["A"])
    }

    func testSigningOutOfTheActiveServerPromotesTheNextOne() {
        let store = InMemoryCredentialStore()
        SessionPersistence.save(session("A", serverId: "a"), to: store)
        SessionPersistence.save(session("B", serverId: "b"), to: store)   // active

        let next = SessionPersistence.remove("b", from: store)

        XCTAssertEqual(next?.serverName, "A")
        XCTAssertEqual(SessionPersistence.load(store)?.serverName, "A")
        XCTAssertEqual(SessionPersistence.all(store).map(\.serverName), ["A"])
    }

    /// Signing out of one that is not being browsed leaves the current one
    /// alone — the whole point of the list.
    func testSigningOutOfABackgroundServerLeavesTheActiveOneUntouched() {
        let store = InMemoryCredentialStore()
        SessionPersistence.save(session("A", serverId: "a"), to: store)
        SessionPersistence.save(session("B", serverId: "b"), to: store)   // active

        let stillActive = SessionPersistence.remove("a", from: store)

        XCTAssertEqual(stillActive?.serverName, "B")
        XCTAssertEqual(SessionPersistence.load(store)?.serverName, "B")
    }

    func testSigningOutOfTheLastServerSignsOutOfTheApp() {
        let store = InMemoryCredentialStore()
        SessionPersistence.save(session("Only", serverId: "only"), to: store)

        XCTAssertNil(SessionPersistence.remove("only", from: store))
        XCTAssertNil(SessionPersistence.load(store))
        XCTAssertTrue(SessionPersistence.all(store).isEmpty)
    }

    func testClearForgetsEveryServer() {
        let store = InMemoryCredentialStore()
        SessionPersistence.save(session("A", serverId: "a"), to: store)
        SessionPersistence.save(session("B", serverId: "b"), to: store)

        SessionPersistence.clear(store)

        XCTAssertTrue(SessionPersistence.all(store).isEmpty)
        XCTAssertNil(SessionPersistence.load(store))
    }

    /// Two servers of the same backend on different addresses are two servers,
    /// even before either has a frozen id.
    func testSessionsWithoutAnIdAreToldApartByAddress() {
        let store = InMemoryCredentialStore()
        SessionPersistence.save(session("Jelly One", host: "one"), to: store)
        SessionPersistence.save(session("Jelly Two", host: "two"), to: store)

        XCTAssertEqual(SessionPersistence.all(store).count, 2)
    }
}
