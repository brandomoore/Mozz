import Foundation
import MozzCore

/// A minimal, serializable description of a signed-in session, persisted to the
/// credential store (Keychain) so the app reconnects on next launch without
/// re-authenticating.
struct StoredSession: Codable, Sendable {
    var kind: BackendKind
    var baseURL: URL
    var token: String
    var userID: String?
    var serverName: String
    var clientIdentifier: String
    var serverMachineIdentifier: String? = nil
    var musicSectionID: String?
    var isDemo: Bool = false
    /// Plex account token (for re-discovering servers in the picker). Nil for
    /// Jellyfin/demo.
    var accountToken: String? = nil
    /// The music library section ids the user chose to sync (Plex). Nil = all
    /// (the default). Decodes to nil for sessions saved before this field.
    var selectedMusicSectionIDs: [String]? = nil
    /// The **server's** machine identifier (Plex). What re-resolution matches on
    /// when the stored address stops answering — the address changes, this does
    /// not. Nil for sessions saved before it was recorded.
    var machineIdentifier: String? = nil
    /// The catalogue's server id, frozen the first time this session is
    /// activated.
    ///
    /// It is otherwise derived by hashing `baseURL`, which quietly makes the
    /// address the identity: repointing a Plex account at a working address
    /// would present as a different server, with an empty catalogue and no
    /// likes or play history. Freezing it lets the address change without
    /// orphaning any of that. See ADR-0017.
    var serverId: String? = nil
}

extension StoredSession {
    /// What makes this the *same* server across saves.
    ///
    /// `serverId` where there is one, because that is the catalogue's identity
    /// and deliberately survives the address changing. Sessions saved before it
    /// was recorded fall back to backend-plus-address, which is what the app
    /// used to derive the id from anyway — so an old entry and its re-saved
    /// self still collapse to one row rather than appearing twice.
    var identity: String {
        if let serverId, !serverId.isEmpty { return serverId }
        return "\(kind.rawValue)\u{0}\(baseURL.absoluteString)"
    }
}

/// Every server this installation is signed in to, with the active one first.
///
/// Mozz's rule is that a platform lacking a capability is behind, never exempt,
/// and the desktop has held several servers and switched between them for as
/// long as it has existed. The phones held exactly one: signing in to a second
/// meant signing out of the first, which on Plex means approving a link again.
/// The catalogue was never the obstacle — it is keyed by server id and has
/// always held several side by side — only this store was.
///
/// First-is-active rather than a separate id, matching Android's accounts file
/// and the desktop's: one ordering to reason about, and no way for the pointer
/// and the list to disagree.
enum SessionPersistence {
    /// The active session, alone. Still written, still read.
    ///
    /// This is the entry routed through iCloud Keychain (see
    /// ``RoutingCredentialStore``), so a sign-in on one device brings the server
    /// up on the user's other devices — and it is what a build without the list
    /// reads. Keeping it in step means an older Mozz on the same account still
    /// signs in, rather than finding nothing and asking for a Plex link.
    static let key = "session.active"

    /// All of them, active first. Device-local: which servers a laptop is
    /// signed in to is not obviously what a phone should adopt wholesale, and
    /// the active one already travels through `key`.
    static let listKey = "session.servers"

    // MARK: One session — unchanged surface

    /// Save this as the active session, and fold it into the list.
    static func save(_ session: StoredSession, to store: any CredentialStore) {
        writeActive(session, to: store)
        var sessions = all(store).filter { $0.identity != session.identity }
        sessions.insert(session, at: 0)
        writeList(sessions, to: store)
    }

    static func load(_ store: any CredentialStore) -> StoredSession? {
        guard let json = try? store.string(forKey: key),
              let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(StoredSession.self, from: data)
    }

    /// Forget every server. Sign out of the app, not of one account.
    static func clear(_ store: any CredentialStore) {
        try? store.setString(nil, forKey: key)
        try? store.setString(nil, forKey: listKey)
    }

    // MARK: Several

    /// Every signed-in server, active first.
    static func all(_ store: any CredentialStore) -> [StoredSession] {
        if let json = try? store.string(forKey: listKey),
           let data = json.data(using: .utf8),
           let sessions = try? JSONDecoder().decode([StoredSession].self, from: data),
           !sessions.isEmpty {
            return sessions
        }
        // No list yet: every installation before this one, and every device that
        // has only ever had `key` synced to it from another. The active session
        // is the list until something writes a longer one.
        return load(store).map { [$0] } ?? []
    }

    /// Make this the active server, keeping the rest.
    ///
    /// Returns nil when the session is not one of the saved ones, which is a
    /// caller asking to switch to something already signed out of rather than
    /// something to force into the list.
    @discardableResult
    static func activate(_ identity: String, in store: any CredentialStore) -> StoredSession? {
        let sessions = all(store)
        guard let chosen = sessions.first(where: { $0.identity == identity }) else { return nil }
        writeActive(chosen, to: store)
        writeList([chosen] + sessions.filter { $0.identity != identity }, to: store)
        return chosen
    }

    /// Sign out of one server. Returns whichever is active afterwards, or nil
    /// when that was the last one and the app is now signed out entirely.
    @discardableResult
    static func remove(_ identity: String, from store: any CredentialStore) -> StoredSession? {
        let remaining = all(store).filter { $0.identity != identity }
        writeList(remaining, to: store)
        guard let next = remaining.first else {
            try? store.setString(nil, forKey: key)
            return nil
        }
        writeActive(next, to: store)
        return next
    }

    /// Replace the whole list, keeping its first entry as the active session.
    ///
    /// For the one caller that has a complete, already-ordered answer — folding
    /// in what the circle knows — rather than a series of single-session saves,
    /// each of which would promote its subject to the front.
    static func replaceAll(_ sessions: [StoredSession], in store: any CredentialStore) {
        guard let active = sessions.first else {
            clear(store)
            return
        }
        writeActive(active, to: store)
        writeList(sessions, to: store)
    }

    // MARK: Writing

    private static func writeActive(_ session: StoredSession, to store: any CredentialStore) {
        guard let data = try? JSONEncoder().encode(session),
              let json = String(data: data, encoding: .utf8) else { return }
        try? store.setString(json, forKey: key)
    }

    private static func writeList(_ sessions: [StoredSession], to store: any CredentialStore) {
        guard !sessions.isEmpty else {
            try? store.setString(nil, forKey: listKey)
            return
        }
        guard let data = try? JSONEncoder().encode(sessions),
              let json = String(data: data, encoding: .utf8) else { return }
        try? store.setString(json, forKey: listKey)
    }
}
