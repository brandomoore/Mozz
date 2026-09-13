package com.thatcube.mozz

import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.thatcube.mozz.core.BackendKind
import com.thatcube.mozz.core.MusicLibrary
import com.thatcube.mozz.core.MozzLibrary
import com.thatcube.mozz.core.MozzPlaybackSettings
import com.thatcube.mozz.core.MozzServer
import com.thatcube.mozz.core.PlaybackSettings
import com.thatcube.mozz.core.PlexHomeUser
import com.thatcube.mozz.core.PlexLink
import com.thatcube.mozz.core.ServerAccount
import com.thatcube.mozz.core.SyncStatus
import com.thatcube.mozz.continuity.ContinuityCoordinator
import com.thatcube.mozz.continuity.ContinuityOffer
import com.thatcube.mozz.playback.MozzAudioProcessor
import com.thatcube.mozz.playback.PlayerController
import com.thatcube.mozz.relay.RelayService
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * Where the app is in getting someone to their music.
 *
 * One linear path, because that is what it is: no account → choose a backend →
 * prove who you are → pick a library if there is a choice → mirror the
 * catalogue → listen. Each state carries what its screen needs and nothing else.
 */
sealed interface AppState {
    /** Opening the library and re-attaching saved accounts. */
    data object Starting : AppState

    /** The backend chooser: Plex, Jellyfin or a Subsonic server. */
    data object SignedOut : AppState

    /**
     * Address, name and password for the two backends that take them.
     *
     * Plex never reaches here — it has no password to type, which is the whole
     * point of its PIN flow — so this state cannot hold [BackendKind.PLEX].
     */
    data class EnteringCredentials(
        val kind: BackendKind,
        val message: String? = null,
    ) : AppState

    /** Plex has issued a PIN; the user approves it in a browser. */
    data class Linking(val link: PlexLink, val waiting: Boolean = true) : AppState

    /**
     * More than one person on this Plex Home, so the choice is theirs.
     *
     * Carries the account token because the choice is not finished until it is
     * made: a managed profile has to be switched to before there is a session
     * at all.
     */
    data class ChoosingProfile(
        val accountToken: String,
        val clientIdentifier: String,
        val users: List<PlexHomeUser>,
    ) : AppState

    /** More than one music library on the server, so the choice is theirs. */
    data class ChoosingLibrary(
        val account: ServerAccount,
        val libraries: List<MusicLibrary>,
    ) : AppState

    /**
     * Mirroring the catalogue.
     *
     * [canBrowse] is what lets someone in before it finishes. A large Jellyfin
     * library takes minutes, and holding a person on a progress bar for that
     * long — when there are already thousands of songs on the device — is a
     * worse answer than letting them look around while the rest arrives. iOS
     * has offered this since it shipped; Android blocked until now.
     */
    data class Syncing(
        val serverName: String,
        val status: SyncStatus?,
        val canBrowse: Boolean = false,
        /** Which backend, so the screen can say what to expect of it. */
        val kind: BackendKind? = null,
    ) : AppState

    data class Ready(val account: ServerAccount) : AppState

    /**
     * [resumeLink] is the Plex link this failed during, if any. Retrying with it
     * resumes the *same* PIN: the user may already have approved it, and issuing
     * a fresh one silently throws that approval away and asks them to do it
     * again — which is what made a transient error look like a broken sign-in.
     */
    data class Failed(
        val message: String,
        val canRetry: Boolean = true,
        val resumeLink: PlexLink? = null,
    ) : AppState
}

class AppViewModel(
    private val server: MozzServer,
    private val library: MozzLibrary,
    /**
     * Null where nothing has wired it — the relay is the one dependency here
     * that a device may legitimately not have, and an optional says so more
     * honestly than a stub that quietly does nothing.
     */
    private val relay: RelayService? = null,
    /**
     * Cross-device resume. Null where nothing wired it, which is the same
     * honesty as [relay]: a device may legitimately not have one.
     */
    private val continuity: ContinuityCoordinator? = null,
    private val playback: PlayerController? = null,
    /** The sound-shaping settings the core owns and the relay carries. */
    private val playbackSettings: MozzPlaybackSettings? = null,
    /**
     * Where to put the levelling flag so the player can read it without a round
     * trip. The core is the record; this is the mirror in front of it.
     */
    private val mirrorNormalization: ((Boolean) -> Unit)? = null,
    /** The equaliser in the running audio sink, while there is one. */
    private val equalizer: () -> MozzAudioProcessor? = { null },
) : ViewModel() {

    private val _continuityOffer = MutableStateFlow<ContinuityOffer?>(null)

    /**
     * What another device left off at, when it is worth offering.
     *
     * Null is the ordinary state: nothing stored, this device's own
     * checkpoint, something already playing here, or a server with no store
     * for it at all — which is every Plex server, and is not a failure.
     */
    val continuityOffer: StateFlow<ContinuityOffer?> = _continuityOffer.asStateFlow()

    fun dismissContinuityOffer() {
        _continuityOffer.value = null
    }

    /**
     * Turn loudness levelling on or off, in the place that syncs.
     *
     * The switch has already moved locally; this is the record. Everything else
     * in the stored settings is carried through untouched — Android has no
     * equalizer screen, and a phone that wrote a flat curve whenever somebody
     * touched this switch would erase the curve its owner set on their desktop.
     */
    suspend fun setNormalization(enabled: Boolean) {
        val client = playbackSettings ?: return
        val current = runCatching { client.get() }.getOrNull() ?: PlaybackSettings()
        runCatching { client.set(current.normalizing(enabled)) }
    }

    /**
     * Adopt whatever the core holds, which may be what another device chose.
     *
     * Read on attach rather than only written: settings that only ever travel
     * outward are not synced settings, they are a local copy with extra steps.
     */
    private fun adoptPlaybackSettings() = viewModelScope.launch {
        val stored = runCatching { playbackSettings?.get() }.getOrNull() ?: return@launch
        mirrorNormalization?.invoke(stored.normalizesVolume)
        applySound(stored)
    }

    /**
     * Read the stored curve so a screen can draw it.
     *
     * Straight from the core rather than from a mirror: the equaliser is the
     * one setting with no local copy, because a ten-band curve is not something
     * worth keeping in two places.
     */
    suspend fun soundSettings(): PlaybackSettings? =
        runCatching { playbackSettings?.get() }.getOrNull()

    /**
     * Write a curve, and put what was actually stored into the running sink.
     *
     * The store normalizes on the way in, so what comes back is the truth; a
     * screen that echoed its own request would show a preamp the filters are
     * not using.
     */
    suspend fun setSound(settings: PlaybackSettings): PlaybackSettings? {
        val stored = runCatching { playbackSettings?.set(settings) }.getOrNull() ?: return null
        applySound(stored)
        mirrorNormalization?.invoke(stored.normalizesVolume)
        return stored
    }

    private fun applySound(settings: PlaybackSettings) {
        equalizer()?.setEqualizer(
            settings.equalizer.gains.toDoubleArray(),
            settings.equalizer.preampDB,
            settings.equalizerEnabled,
        )
    }

    private val _state = MutableStateFlow<AppState>(AppState.Starting)
    val state: StateFlow<AppState> = _state.asStateFlow()

    init {
        restore()
    }

    /**
     * Re-attach whatever was signed in last time.
     *
     * The core forgets tokens between launches by design, so nothing works until
     * the saved account is attached again — including playback of an album the
     * user was halfway through.
     */
    private fun restore() = viewModelScope.launch {
        _state.value = AppState.Starting
        runCatching {
            val account = server.savedAccounts().firstOrNull()
                ?: return@runCatching null
            server.attach(account)
            account
        }.onSuccess { account ->
            when {
                account == null -> _state.value = AppState.SignedOut
                // Attached, but nothing was ever mirrored — a sign-in that broke
                // partway leaves exactly this state, and showing an empty Home
                // makes it look like the server has no music.
                library.counts(account.serverId).tracks == 0 -> sync(account)
                else -> {
                    _state.value = AppState.Ready(account)
                    verifyReachable(account)
                    flushFavorites(account.serverId)
                    syncCircle(account)
                    watchContinuity(account)
                    adoptPlaybackSettings()
                }
            }
        }.onFailure { error ->
            // A stored account that will not attach is not fatal — the token may
            // simply have been revoked. Offer signing in again rather than a
            // dead screen.
            fail("Reopening your library", error)
        }
    }

    /**
     * The chooser's answer.
     *
     * Plex goes straight to its PIN flow because there is nothing to type;
     * Jellyfin and Subsonic need an address and a name first.
     */
    fun chooseBackend(kind: BackendKind) {
        if (kind == BackendKind.PLEX) beginPlexLink()
        else _state.value = AppState.EnteringCredentials(kind)
    }

    /** Back out of a credentials form or a Plex link, to the chooser. */
    fun chooseAnotherBackend() {
        _state.value = AppState.SignedOut
    }

    /**
     * Sign in to a Jellyfin or Subsonic server.
     *
     * The address is normalised here rather than in the form: people type
     * "192.168.1.8:8096" and "navidrome.example.com/", and a scheme-less or
     * slash-trailing URL is a connection failure with a message about the URL
     * being wrong, which reads as Mozz not supporting their server.
     */
    fun connectCredentials(
        kind: BackendKind,
        baseUrl: String,
        username: String,
        password: String,
    ) = viewModelScope.launch {
        val address = normalizeBaseUrl(baseUrl)
        if (address.isEmpty()) {
            _state.value = AppState.EnteringCredentials(kind, "Enter your server's address.")
            return@launch
        }
        _state.value = AppState.Starting
        runCatching {
            server.connect(kind, address, username, password.takeIf { it.isNotEmpty() })
        }
            .onSuccess { account -> chooseLibraryOrSync(account) }
            // Straight back to the form, with the reason, rather than to the
            // generic failure screen: a typo'd address or password is something
            // to correct in place, not something to start over from.
            .onFailure { error ->
                Log.e(TAG, "Signing in to ${kind.display} failed", error)
                _state.value = AppState.EnteringCredentials(
                    kind,
                    error.message ?: "That server did not accept those details.",
                )
            }
    }

    /** Ask Plex for a PIN. The returned link is what the user opens in a browser. */
    fun beginPlexLink() = viewModelScope.launch {
        _state.value = AppState.Starting
        runCatching { server.beginPlexLink() }
            .onSuccess { link ->
                _state.value = AppState.Linking(link)
                awaitLink(link)
            }
            .onFailure { fail("Asking Plex for a PIN", it) }
    }

    private fun awaitLink(link: PlexLink) = viewModelScope.launch {
        runCatching { server.awaitPlexAccountToken(link) }
            .onSuccess { accountToken -> chooseProfileOrComplete(accountToken, link) }
            .onFailure { fail("Plex link", it, resumeLink = link) }
    }

    /**
     * Ask who this is, when the account holds more than one person.
     *
     * One person is not a decision worth interrupting anybody for, and neither
     * is a Home the account cannot tell us about: if the lookup fails we sign
     * in as the account owner, which is exactly what happened before this
     * existed. Sign-in must not hinge on an optional Plex feature.
     */
    private suspend fun chooseProfileOrComplete(accountToken: String, link: PlexLink) {
        val users = runCatching { server.plexHomeUsers(accountToken, link.clientIdentifier) }
            .getOrDefault(emptyList())
        if (users.size > 1) {
            _state.value = AppState.ChoosingProfile(accountToken, link.clientIdentifier, users)
            return
        }
        completeLogin(accountToken, link.clientIdentifier, users.firstOrNull(), profilePin = null)
    }

    fun selectProfile(
        accountToken: String,
        clientIdentifier: String,
        user: PlexHomeUser,
        profilePin: String? = null,
    ) = viewModelScope.launch {
        _state.value = AppState.Starting
        completeLogin(accountToken, clientIdentifier, user, profilePin)
    }

    private suspend fun completeLogin(
        accountToken: String,
        clientIdentifier: String,
        user: PlexHomeUser?,
        profilePin: String?,
    ) {
        runCatching { server.completePlexLogin(accountToken, clientIdentifier, user, profilePin) }
            .onSuccess { account -> chooseLibraryOrSync(account) }
            .onFailure { fail("Signing in", it) }
    }

    /**
     * Plex addresses its catalogue by library section, and a freshly linked
     * account has none. One music library is not a decision worth interrupting
     * someone for; several is.
     */
    private suspend fun chooseLibraryOrSync(account: ServerAccount) {
        runCatching {
            server.attach(account)
            server.libraries(account.serverId)
        }.onSuccess { libraries ->
            when {
                libraries.isEmpty() -> _state.value = AppState.Failed(
                    "${account.serverName} has no music library for Mozz to sync.",
                    canRetry = false,
                )
                libraries.size == 1 -> selectLibrary(account, libraries.first().id)
                else -> _state.value = AppState.ChoosingLibrary(account, libraries)
            }
        }.onFailure { fail("Reading libraries", it) }
    }

    fun selectLibrary(account: ServerAccount, libraryId: String) = viewModelScope.launch {
        runCatching { server.selectMusicLibrary(account, libraryId) }
            .onSuccess { sync(it) }
            .onFailure { fail("Selecting a library", it) }
    }

    /**
     * Check that the address this account is pinned to still answers, and quietly
     * move to one that does if it does not.
     *
     * Runs after the library is already on screen, not before, because it costs a
     * round trip and the catalogue is local — making launch wait on the network
     * to show music that is already on the device would be a bad trade. The
     * symptom this catches is otherwise silent and total: every cover grey, every
     * track refusing to play, with a library that looks intact. See ADR-0017.
     */
    private fun verifyReachable(account: ServerAccount) = viewModelScope.launch {
        // `libraries` is a real request to the server (Plex answers it from
        // library/sections), so it fails exactly when the address is dead.
        val repointed = if (runCatching { server.libraries(account.serverId) }.isSuccess) {
            // It answers — but answering is not the same as being the right
            // address. A phone that fell back to its server's public address
            // keeps it for as long as it works, sending every byte of audio out
            // of the house and back while the server sits on the same wifi.
            runCatching { server.preferLocalAddress(account) }.getOrNull()
        } else {
            runCatching { server.repointAccount(account) }.getOrNull()
        } ?: return@launch
        if (_state.value is AppState.Ready) _state.value = AppState.Ready(repointed)
    }

    /**
     * What the running sync is doing, for the library to show while it runs.
     *
     * Separate from [AppState] because a sync is not always a screen. The first
     * one is — there is nothing to browse yet — but a resync of a library that
     * is already on the device is background work, and throwing the user back
     * to a full-page progress bar for it took the app away to report on
     * something they could have watched from inside it. iOS has shown this as a
     * card on Home since it shipped.
     */
    private val _syncProgress = MutableStateFlow<SyncStatus?>(null)
    val syncProgress: StateFlow<SyncStatus?> = _syncProgress.asStateFlow()

    private fun sync(account: ServerAccount) = viewModelScope.launch {
        // Only take over the screen when there is nothing behind it to take
        // over from. A resync from Settings publishes progress and leaves the
        // library where it is.
        val inBackground = _state.value is AppState.Ready
        if (!inBackground) _state.value = AppState.Syncing(account.serverName, null, kind = account.kind)
        var target = account
        runCatching {
            // Not a plain attach. A Plex account carries no library section
            // until something resolves one, and syncing without it fails with
            // "Plex music section not resolved" every time it is retried. The
            // library picker resolves it at onboarding — but an account whose
            // onboarding was interrupted reaches here without ever having been
            // asked, and would then be permanently unsyncable.
            target = server.attachForSync(target)
            server.sync(target.serverId).collect { status -> report(target.serverName, status, target.kind) }
        }.recoverCatching { error ->
            // A sync that fails against a dead address fails the same way every
            // time it is retried, because every retry goes to the same address.
            // Ask the account for a working one and run it again — once. A null
            // means there was nothing better to move to, and the original error
            // is the honest one to report.
            target = server.attachForSync(server.repointAccount(target) ?: throw error)
            server.sync(target.serverId).collect { status -> report(target.serverName, status, target.kind) }
        }.onSuccess {
            _syncProgress.value = null
            _state.value = AppState.Ready(target)
            flushFavorites(target.serverId)
            syncCircle(target)
            watchContinuity(target)
            adoptPlaybackSettings()
        }
            .onFailure { error ->
                _syncProgress.value = null
                // A resync that fails has a library behind it, and replacing
                // that with an error page loses more than the error is worth.
                // Failing loudly is right only when there is nothing to lose.
                if (inBackground) Log.e(TAG, "Resync failed", error) else fail("Sync", error)
            }
    }

    /**
     * Post a sync update — unless the user has already gone in to browse, in
     * which case the progress screen is behind them and putting it back would
     * be the app taking the library away again.
     */
    private fun report(serverName: String, status: SyncStatus, kind: BackendKind?) {
        _syncProgress.value = status.takeIf { it.running }
        // The progress screen is only updated while it is the screen. Once the
        // user has gone in to browse, putting it back would be the app taking
        // the library away again.
        if (_state.value !is AppState.Syncing) return
        _state.value = AppState.Syncing(serverName, status, status.hasSomethingToShow, kind)
    }

    /**
     * Give a typed address the shape a URL needs.
     *
     * No scheme means http, because a self-hosted server on a home network
     * usually has no certificate; someone who needs https types it.
     */
    internal fun normalizeBaseUrl(raw: String): String {
        val trimmed = raw.trim().trimEnd('/')
        if (trimmed.isEmpty()) return ""
        return if (trimmed.contains("://")) trimmed else "http://$trimmed"
    }

    /**
     * Send likes and ratings that never reached the server.
     *
     * Called where the server has just proved it answers — a fresh attach and a
     * finished sync — because those are the two moments something queued while
     * offline is most likely to go through. Failure is not reported: a like
     * that stays queued is exactly what the queue is for.
     */
    private fun flushFavorites(serverId: String) = viewModelScope.launch {
        runCatching { library.flushFavoriteOutbox(serverId) }
    }

    /**
     * Trade with the rest of the circle: listening history out and back, and
     * the analysed vectors this phone would otherwise spend an evening
     * recomputing.
     *
     * Does nothing on a device that has not been paired, which is not a
     * failure and is not reported as one. Fired at the same two moments the
     * favourite flush is, for the same reason: those are when the network has
     * just proved it works.
     */
    private fun syncCircle(account: ServerAccount) = viewModelScope.launch {
        runCatching { relay?.sync(account) }
    }

    /**
     * Read what another device left, then start writing what this one is doing.
     *
     * In that order and not the other way round: a phone paused in a pocket
     * while a laptop took over would otherwise publish what it remembered and
     * clobber the newer session before it had read it.
     */
    private fun watchContinuity(account: ServerAccount) = viewModelScope.launch {
        val coordinator = continuity ?: return@launch
        val player = playback ?: return@launch
        _continuityOffer.value = runCatching {
            coordinator.reconcile(
                serverId = account.serverId,
                isPlayingLocally = player.state.value.isPlaying,
            )
        }.getOrNull()

        player.onCheckpoint = { reason ->
            val snapshot = player.state.value
            viewModelScope.launch {
                coordinator.checkpoint(
                    reason = reason,
                    account = account,
                    queue = snapshot.queue,
                    indexInQueue = snapshot.indexInQueue,
                    positionMS = snapshot.positionMillis,
                    isPlaying = snapshot.intendsToPlay,
                    repeatMode = snapshot.repeat.name.lowercase(),
                    isShuffled = snapshot.shuffle,
                )
            }
        }
    }

    /**
     * Take up the offer: rebuild what the other device was playing and drop in
     * where it left off.
     *
     * The queue is resolved a track at a time through the catalogue, because a
     * checkpoint carries locators and titles rather than playable rows. A queue
     * that cannot be rebuilt still leaves the one song, which is the part
     * somebody actually wanted back.
     */
    fun resumeContinuity() = viewModelScope.launch {
        val offer = _continuityOffer.value ?: return@launch
        val account = (state.value as? AppState.Ready)?.account ?: return@launch
        val player = playback ?: return@launch
        _continuityOffer.value = null

        val cursor = offer.snapshot.cursor
        val hydrated = offer.snapshot.hydratedTracks.associateBy { it.remoteId }
        val wanted = offer.snapshot.queue?.items?.map { it.locator.remoteId }
            ?: listOf(cursor.current.remoteId)
        val tracks = wanted.take(RESUME_QUEUE_LIMIT).mapNotNull { remoteId ->
            hydrated[remoteId]
                ?: runCatching { library.track(account.serverId, remoteId) }.getOrNull()
        }
        if (tracks.isEmpty()) return@launch

        val startAt = tracks.indexOfFirst { it.remoteId == cursor.current.remoteId }.coerceAtLeast(0)
        player.play(tracks, startAt).join()
        if (cursor.positionMS > 0) player.seekTo(cursor.positionMS)
    }

    /** Re-mirror the catalogue for the account already signed in. */
    fun resync() {
        (state.value as? AppState.Ready)?.let { sync(it.account) }
    }

    /**
     * Go to the library while the sync is still running.
     *
     * Nothing is cancelled: the collector in [sync] keeps running and will move
     * to Ready as usual when it finishes, so this is only about which screen is
     * in front. The guard is that it only applies while syncing — a stray tap
     * arriving after completion must not push a stale account into Ready.
     */
    fun browseWhileSyncing() {
        val syncing = _state.value as? AppState.Syncing ?: return
        val account = server.savedAccounts().firstOrNull() ?: return
        if (!syncing.canBrowse) return
        _state.value = AppState.Ready(account)
    }

    fun signOut() = viewModelScope.launch {
        server.forgetAllAccounts()
        _state.value = AppState.SignedOut
    }

    /**
     * Resume from wherever this broke, in order of how much would otherwise be
     * lost: an approved Plex PIN first, then a signed-in account that has not
     * finished mirroring, and only then a cold restart.
     */
    fun retry() {
        val failure = state.value as? AppState.Failed
        val link = failure?.resumeLink
        when {
            link != null -> {
                _state.value = AppState.Linking(link)
                awaitLink(link)
            }
            server.savedAccounts().isNotEmpty() -> viewModelScope.launch {
                chooseLibraryOrSync(server.savedAccounts().first())
            }
            else -> restore()
        }
    }

    private fun fail(what: String, error: Throwable, resumeLink: PlexLink? = null) {
        // Logged as well as shown: an on-screen message the user reads aloud is
        // not a stack trace, and this is exactly where a wire-shape mismatch
        // surfaces.
        Log.e(TAG, "$what failed", error)
        _state.value = AppState.Failed(
            message = error.message ?: "$what did not work.",
            resumeLink = resumeLink,
        )
    }

    companion object {
        val Factory: ViewModelProvider.Factory = viewModelFactory {
            initializer {
                val application =
                    this[ViewModelProvider.AndroidViewModelFactory.APPLICATION_KEY]
                        as MozzApplication
                AppViewModel(
                    application.server,
                    application.library,
                    application.relay,
                    application.continuity,
                    application.playback,
                    application.playbackSettings,
                    { application.settings.normalizeVolume = it },
                    { application.equalizer },
                )
            }
        }

        private const val TAG = "Mozz"
    }
}

/**
 * How much of another device's queue to rebuild.
 *
 * A screen's worth, not a library: resolving is a round trip per track, and
 * nobody resumes into two hundred songs they need immediately.
 */
private const val RESUME_QUEUE_LIMIT = 200
