import SwiftUI
import MozzCore

/// Every server signed in to, which one is being browsed, and the way to add
/// another.
///
/// Mozz's rule is that a platform lacking a capability is behind, never exempt.
/// The desktop has held several servers and switched between them for as long as
/// it has existed; the phone held exactly one, so signing in to a second meant
/// signing out of the first — and on Plex that means approving a link again,
/// which is a real cost for the ordinary case of a Plex box at home and a
/// Navidrome on a VPS.
///
/// Switching is not a sign-out and a sign-in. Both catalogues stay on the
/// device, both tokens stay in the Keychain, and switching back costs nothing.
struct ServersView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var addingServer = false
    /// Held while the confirmation is up, so the alert knows which row it is
    /// about — a row that may well have moved by the time it is answered.
    @State private var signingOutOf: StoredSession?

    var body: some View {
        List {
            Section {
                ForEach(env.servers, id: \.identity) { server in
                    row(server)
                }
            } header: {
                Text(env.servers.count == 1 ? "Server" : "Servers")
            } footer: {
                Text("Mozz keeps each server's music separately. Switching is instant — nothing is downloaded again.")
            }

            Section {
                Button {
                    addingServer = true
                } label: {
                    Label("Add a Server", mozz: "plus")
                }
            }

            if env.servers.count > 1 {
                Section {
                    Button(role: .destructive) { env.signOut() } label: {
                        Text("Sign Out of All").frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .navigationTitle("Servers")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $addingServer) {
            AddServerSheet(isPresented: $addingServer)
                .environmentObject(env)
        }
        .onAppear { env.refreshServers() }
        .alert(
            "Sign out of \(signingOutOf?.serverName ?? "this server")?",
            isPresented: Binding(
                get: { signingOutOf != nil },
                set: { if !$0 { signingOutOf = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) { signingOutOf = nil }
            Button("Sign Out", role: .destructive) {
                if let server = signingOutOf { env.signOut(server) }
                signingOutOf = nil
            }
        } message: {
            Text("Its music is removed from this device. Your other servers are untouched.")
        }
    }

    @ViewBuilder
    private func row(_ server: StoredSession) -> some View {
        let isActive = server.identity == env.activeServerIdentity
        Button {
            guard !isActive else { return }
            env.switchTo(server)
        } label: {
            HStack(spacing: 12) {
                BrandChip(brand: brand(for: server.kind), size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(server.serverName)
                        .font(.body)
                        .foregroundStyle(.primary)
                    // The address, not the backend's name: the chip already says
                    // which product it is, and with two Jellyfins on one account
                    // the address is the only thing telling them apart.
                    Text(server.baseURL.host ?? server.baseURL.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if isActive {
                    Image(mozz: "checkmark")
                        .resizable().scaledToFit()
                        .frame(width: 13, height: 13)
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(server.serverName))
        .accessibilityValue(Text(isActive ? "Current server" : "Tap to switch"))
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { signingOutOf = server } label: {
                Label("Sign Out", mozz: "xmark.circle")
            }
        }
    }

    private func brand(for kind: BackendKind) -> BrandStyle {
        switch kind {
        case .plex: return .plex
        case .jellyfin: return .jellyfin
        case .subsonic: return .navidrome
        }
    }
}

/// Signing in to an additional server, from inside the app.
///
/// The same picker onboarding opens on, because a second server is signed in to
/// exactly the way the first was — there is no reason for two flows and every
/// reason not to maintain two. It closes itself once the new server is up: the
/// environment flips `active` when activation finishes, and that is the signal.
private struct AddServerSheet: View {
    @EnvironmentObject private var env: AppEnvironment
    @Binding var isPresented: Bool
    /// What was active when the sheet opened. Activation replacing it is the
    /// only reliable "it worked" — the sign-in views hand off to an
    /// environment-owned task and return long before it finishes.
    @State private var startingIdentity: String?

    var body: some View {
        OnboardingView()
            .onAppear { startingIdentity = env.activeServerIdentity }
            .onChange(of: env.activeServerIdentity) { _, now in
                if let now, now != startingIdentity { isPresented = false }
            }
    }
}
