package com.thatcube.mozz.ui

import androidx.annotation.DrawableRes
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Icon
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import com.thatcube.mozz.core.BackendKind
import com.thatcube.mozz.core.SyncPhaseRow
import com.thatcube.mozz.core.SyncProgressSmoother
import kotlinx.coroutines.delay
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.runtime.setValue
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.mutableStateOf
import androidx.compose.material3.OutlinedTextField
import androidx.compose.foundation.text.KeyboardOptions
import com.thatcube.mozz.core.PlexHomeUser
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.thatcube.mozz.R
import com.thatcube.mozz.core.MusicLibrary
import com.thatcube.mozz.core.SyncStatus
import com.thatcube.mozz.ui.theme.LocalMozzBlackout
import com.thatcube.mozz.ui.theme.quietBody

/**
 * The shell every onboarding step sits in.
 *
 * Vertical rhythm per mozz-design-refs/REDESIGN-PLAN.md: the wordmark and
 * tagline in the upper third, the content centred, the licence footer pinned to
 * the bottom — so the whitespace reads as intentional rather than as an empty
 * screen with the controls fallen to the floor.
 *
 * The content is width-capped rather than filling. On the Fold's inner screen, a
 * sign-in form stretched to 8 inches looks broken; a column of a comfortable
 * reading width, centred, does not.
 */
@Composable
private fun OnboardingScaffold(
    title: String,
    subtitle: String? = null,
    content: @Composable () -> Unit,
) {
    Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .safeDrawingPadding()
                .padding(horizontal = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Spacer(Modifier.height(64.dp))
            Image(
                painter = painterResource(R.drawable.mozz_logo),
                contentDescription = null,
                modifier = Modifier.size(72.dp),
            )
            Spacer(Modifier.height(14.dp))
            Text("Mozz", style = MaterialTheme.typography.displaySmall)
            Spacer(Modifier.height(8.dp))
            Text(
                "One app for your music, wherever it lives.",
                style = quietBody,
            )

            Spacer(Modifier.weight(0.45f))

            Column(
                modifier = Modifier.widthIn(max = 420.dp).fillMaxWidth(),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text(
                    title,
                    style = MaterialTheme.typography.headlineMedium,
                    textAlign = TextAlign.Center,
                )
                if (subtitle != null) {
                    Spacer(Modifier.height(10.dp))
                    Text(subtitle, style = quietBody)
                }
                Spacer(Modifier.height(28.dp))
                content()
            }

            Spacer(Modifier.weight(1f))

            Text(
                "Free forever. Open source, GPL-3.0.",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.height(24.dp))
        }
    }
}

/**
 * Identity for a backend, shared by the chooser row and the credentials form.
 *
 * The mirror of iOS's `BrandStyle`, down to the tints — the products are
 * recognised by their colours, and three identical grey glyphs make the choice
 * harder than it needs to be. The marks come from `tools/icons/brand-svg/`,
 * which is the same source iOS reads.
 */
private data class Brand(
    val kind: BackendKind,
    @DrawableRes val logo: Int,
    /** What the row says. Usually the product's name. */
    val pickerName: String,
    val tint: Color,
    /** One line under the form's heading, or null where the heading says enough. */
    val hint: String?,
) {
    companion object {
        val plex = Brand(
            BackendKind.PLEX, R.drawable.brand_plex, "Plex",
            Color(0xFFE5A00D),
            "You approve the connection in your browser. No password is typed here.",
        )
        val jellyfin = Brand(
            BackendKind.JELLYFIN, R.drawable.brand_jellyfin, "Jellyfin",
            Color(0xFF8761F2),
            "Your Jellyfin address, and the name and password you sign in with there.",
        )

        // Navidrome's mark for a Subsonic row: the protocol has no mark of its
        // own, and Navidrome is what nearly everyone speaking it is running.
        // The label carries the accuracy the logo cannot.
        val subsonic = Brand(
            BackendKind.SUBSONIC, R.drawable.brand_navidrome, "Navidrome (Subsonic)",
            Color(0xFF2E86D6),
            "Any Subsonic or OpenSubsonic server — Navidrome, Gonic, Ampache, LMS.",
        )

        val all = listOf(jellyfin, plex, subsonic)

        fun of(kind: BackendKind) = all.first { it.kind == kind }
    }
}

/**
 * A backend's mark in a soft circle of its own colour, for anywhere a saved
 * server is listed rather than chosen.
 */
@Composable
fun BackendChip(kind: BackendKind, size: Dp = 34.dp) {
    BrandChip(Brand.of(kind), size)
}

/** A backend's mark in a soft circle of its own colour. iOS's `BrandChip`. */
@Composable
private fun BrandChip(brand: Brand, size: Dp = 40.dp) {
    Box(
        modifier = Modifier
            .size(size)
            .background(brand.tint.copy(alpha = 0.18f), CircleShape),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            painterResource(brand.logo),
            contentDescription = null,
            tint = brand.tint,
            // Plex's chevron occupies about half of its 24x24 canvas where the
            // other two very nearly fill theirs, so an equal inset renders it
            // visibly smaller. Same correction iOS makes.
            modifier = Modifier.size(size * if (brand.kind == BackendKind.PLEX) 0.68f else 0.56f),
        )
    }
}

/**
 * The backend chooser.
 *
 * Android offered Plex and only Plex until now, while the shared core has
 * spoken Jellyfin and Subsonic for as long as it has spoken Plex and both
 * other clients offered all three. One grouped card with hairline dividers,
 * matching iOS's picker and the library picker below.
 */
@Composable
fun SignInScreen(onChoose: (BackendKind) -> Unit, onCancel: (() -> Unit)? = null) {
    OnboardingScaffold(
        title = if (onCancel == null) "Connect your server" else "Add a server",
        subtitle = "Mozz plays the music on a server you run. Pick the one you have.",
    ) {
        Surface(
            color = MaterialTheme.colorScheme.surfaceVariant,
            shape = MaterialTheme.shapes.large,
            border = if (LocalMozzBlackout.current) {
                BorderStroke(1.dp, MaterialTheme.colorScheme.outline)
            } else {
                null
            },
            modifier = Modifier.fillMaxWidth(),
        ) {
            Column {
                Brand.all.forEachIndexed { index, brand ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { onChoose(brand.kind) }
                            .padding(horizontal = 16.dp, vertical = 14.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        BrandChip(brand)
                        Spacer(Modifier.width(14.dp))
                        Text(
                            brand.pickerName,
                            style = MaterialTheme.typography.titleMedium,
                            color = MaterialTheme.colorScheme.onSurface,
                            modifier = Modifier.weight(1f),
                        )
                        Icon(
                            painterResource(R.drawable.ic_chevron_right),
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.size(18.dp),
                        )
                    }
                    if (index != Brand.all.lastIndex) {
                        // Inset to clear the chip, so the rules line up with the
                        // row text rather than cutting under the logos.
                        HorizontalDivider(
                            color = MaterialTheme.colorScheme.outlineVariant,
                            modifier = Modifier.padding(start = 16.dp + 40.dp + 14.dp),
                        )
                    }
                }
            }
        }

        // Only when there is something to go back to. On a first run there is
        // not, and offering a way out would be offering a dead end.
        if (onCancel != null) {
            Spacer(Modifier.height(12.dp))
            TextButton(onClick = onCancel) { Text("Cancel") }
        }
    }
}

/**
 * Address, name and password, for the two backends that take them.
 *
 * Password is optional on purpose: a Subsonic server may be set up without one,
 * and requiring it would lock those users out of an app that can talk to their
 * server perfectly well.
 */
@Composable
fun CredentialsScreen(
    kind: BackendKind,
    message: String?,
    onSubmit: (baseUrl: String, username: String, password: String) -> Unit,
    onBack: () -> Unit,
    onCancel: (() -> Unit)? = null,
) {
    val brand = Brand.of(kind)
    var address by remember(kind) { mutableStateOf("") }
    var username by remember(kind) { mutableStateOf("") }
    var password by remember(kind) { mutableStateOf("") }

    OnboardingScaffold(title = "Sign in to ${brand.kind.display}", subtitle = brand.hint) {
        OutlinedTextField(
            value = address,
            onValueChange = { address = it },
            label = { Text("Server address") },
            placeholder = { Text(if (kind == BackendKind.JELLYFIN) "192.168.1.8:8096" else "music.example.com") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
            modifier = Modifier.fillMaxWidth(),
        )
        Spacer(Modifier.height(12.dp))
        OutlinedTextField(
            value = username,
            onValueChange = { username = it },
            label = { Text("Username") },
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
        )
        Spacer(Modifier.height(12.dp))
        OutlinedTextField(
            value = password,
            onValueChange = { password = it },
            label = { Text("Password") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
            visualTransformation = PasswordVisualTransformation(),
            modifier = Modifier.fillMaxWidth(),
        )

        if (message != null) {
            Spacer(Modifier.height(14.dp))
            Text(
                message,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.error,
                textAlign = TextAlign.Center,
            )
        }

        Spacer(Modifier.height(20.dp))
        Button(
            onClick = { onSubmit(address, username, password) },
            enabled = address.isNotBlank() && username.isNotBlank(),
            modifier = Modifier.fillMaxWidth().height(52.dp),
        ) {
            Text("Sign in", style = MaterialTheme.typography.labelLarge)
        }
        Spacer(Modifier.height(8.dp))
        TextButton(onClick = onBack) { Text("Use a different server") }
        if (onCancel != null) {
            TextButton(onClick = onCancel) { Text("Cancel") }
        }
    }
}

/**
 * No code is shown, deliberately.
 *
 * The core asks Plex for a `strong` PIN, because that is the only kind
 * `app.plex.tv/auth` will claim — and a strong PIN's code is a 25-character
 * token, not the four characters you type at plex.tv/link. Putting it on screen
 * would be an unreadable credential presented as if it were an instruction.
 * The link button is the whole flow.
 */
@Composable
fun LinkingScreen(onOpenBrowser: () -> Unit, onCancel: () -> Unit) {
    OnboardingScaffold(
        title = "Approve Mozz on Plex",
        subtitle = "Plex will open in your browser and ask you to confirm this " +
            "device. Come back here when it says you are linked.",
    ) {
        Button(
            onClick = onOpenBrowser,
            modifier = Modifier.fillMaxWidth().height(52.dp),
        ) {
            Text("Open Plex to approve", style = MaterialTheme.typography.labelLarge)
        }
        Spacer(Modifier.height(16.dp))
        WaitingForPlex()
        Spacer(Modifier.height(8.dp))
        TextButton(onClick = onCancel) { Text("Cancel") }
    }
}

@Composable
private fun WaitingForPlex() {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        CircularProgressIndicator(
            modifier = Modifier.size(18.dp),
            strokeWidth = 2.dp,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.height(10.dp))
        Text("Waiting for Plex…", style = quietBody)
    }
}

@Composable
fun LibraryPickerScreen(
    serverName: String,
    libraries: List<MusicLibrary>,
    onSelect: (MusicLibrary) -> Unit,
) {
    OnboardingScaffold(
        title = "Which library?",
        subtitle = "$serverName has more than one. Mozz will mirror the one you pick.",
    ) {
        // One inset card with hairline dividers, not a stack of filled pills —
        // the picker in the redesign plan.
        Surface(
            color = MaterialTheme.colorScheme.surfaceVariant,
            shape = MaterialTheme.shapes.large,
            // In Black the card's colour is the page's, so the hairline is the
            // only thing that makes it a card.
            border = if (LocalMozzBlackout.current) {
                BorderStroke(1.dp, MaterialTheme.colorScheme.outline)
            } else {
                null
            },
            modifier = Modifier.fillMaxWidth(),
        ) {
            LazyColumn(contentPadding = PaddingValues(vertical = 4.dp)) {
                items(libraries, key = { it.id }) { library ->
                    TextButton(
                        onClick = { onSelect(library) },
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Text(
                            library.name,
                            style = MaterialTheme.typography.titleMedium,
                            color = MaterialTheme.colorScheme.onSurface,
                            modifier = Modifier.fillMaxWidth().padding(vertical = 10.dp),
                        )
                    }
                    if (library != libraries.last()) {
                        HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                    }
                }
            }
        }
    }
}

/**
 * Which person on this Plex Home is signing in.
 *
 * A household shares one Plex account and each member has their own play
 * counts, ratings and sometimes their own libraries. Signing in without asking
 * files everything under whoever owns the account — which is what Android did
 * until now, silently.
 *
 * A profile with a PIN takes it here rather than on a second screen: the PIN is
 * the same decision as the name, and splitting one decision across two pages is
 * how a picker starts feeling like a form.
 */
@Composable
fun ProfilePickerScreen(
    users: List<PlexHomeUser>,
    onSelect: (PlexHomeUser, String?) -> Unit,
) {
    var pinFor by remember { mutableStateOf<PlexHomeUser?>(null) }
    var pin by remember { mutableStateOf("") }

    OnboardingScaffold(
        title = "Who is listening?",
        subtitle = "This Plex account has more than one person on it. " +
            "Ratings and play counts follow whoever you pick.",
    ) {
        Surface(
            color = MaterialTheme.colorScheme.surfaceVariant,
            shape = MaterialTheme.shapes.large,
            border = if (LocalMozzBlackout.current) {
                BorderStroke(1.dp, MaterialTheme.colorScheme.outline)
            } else {
                null
            },
            modifier = Modifier.fillMaxWidth(),
        ) {
            LazyColumn(contentPadding = PaddingValues(vertical = 4.dp)) {
                items(users, key = { it.id }) { user ->
                    TextButton(
                        onClick = {
                            if (user.requiresPin) {
                                pinFor = user
                                pin = ""
                            } else {
                                onSelect(user, null)
                            }
                        },
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Text(
                            if (user.requiresPin) "${user.name} · PIN" else user.name,
                            style = MaterialTheme.typography.titleMedium,
                            color = MaterialTheme.colorScheme.onSurface,
                            modifier = Modifier.fillMaxWidth().padding(vertical = 10.dp),
                        )
                    }
                    if (user != users.last()) {
                        HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                    }
                }
            }
        }

        pinFor?.let { user ->
            Spacer(Modifier.height(20.dp))
            OutlinedTextField(
                value = pin,
                onValueChange = { entered -> pin = entered.filter { it.isDigit() }.take(8) },
                label = { Text("${user.name}'s PIN") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
                visualTransformation = PasswordVisualTransformation(),
                modifier = Modifier.fillMaxWidth(),
            )
            Spacer(Modifier.height(12.dp))
            Button(
                onClick = { onSelect(user, pin) },
                enabled = pin.isNotEmpty(),
                modifier = Modifier.fillMaxWidth(),
            ) { Text("Continue as ${user.name}") }
        }
    }
}

/**
 * The scan, with its own account of itself.
 *
 * This was one unlabelled bar and a line of text — the same picture for "three
 * minutes in, songs nearly done" as for "stuck on artists". The core has always
 * sent a per-phase breakdown and both other clients have always drawn it; this
 * is Android catching up.
 *
 * The counters are paced by [SyncProgressSmoother] rather than bound straight
 * to the reports, which arrive a page at a time and so would sit still and then
 * leap. Same constants as iOS and the desktop, so the same library counts at
 * the same speed on every device.
 */
@Composable
fun SyncingScreen(
    serverName: String,
    status: SyncStatus?,
    canBrowse: Boolean = false,
    kind: BackendKind? = null,
    onBrowseNow: () -> Unit = {},
) {
    OnboardingScaffold(
        title = "Mirroring $serverName",
        // What to expect, which depends on the backend: Plex serves its
        // catalogue fast, a self-hosted Jellyfin on a large library can take
        // several minutes, and Subsonic is walked album by album. Setting that
        // expectation up front is the difference between "slow" and "broken".
        // iOS has said this since it shipped.
        subtitle = when (kind) {
            BackendKind.PLEX ->
                "Your catalogue is copied to this device — usually quick with Plex — so browsing " +
                    "and searching stay instant even when the server is not."
            BackendKind.JELLYFIN ->
                "Your catalogue is copied to this device, so browsing and searching stay instant " +
                    "even when the server is not. A large Jellyfin library can take a few minutes."
            BackendKind.SUBSONIC ->
                "Your catalogue is copied to this device, so browsing and searching stay instant " +
                    "even when the server is not. Mozz walks your albums to sync safely, so a " +
                    "large library takes a few minutes."
            null ->
                "Your catalogue is copied to this device, so browsing and searching stay instant " +
                    "even when the server is not."
        },
    ) {
        val smoother = remember { SyncProgressSmoother() }

        // Re-paced on every report, and again on a timer between them: the
        // easing has to keep moving while nothing new is arriving, which is
        // exactly the stretch it exists for.
        var rows by remember { mutableStateOf(emptyList<SyncPhaseRow>()) }
        LaunchedEffect(status) { rows = smoother.update(status) }
        LaunchedEffect(Unit) {
            while (true) {
                delay(250)
                rows = smoother.update(status)
            }
        }

        val fraction = status?.fraction
        if (fraction != null) {
            LinearProgressIndicator(progress = { fraction }, modifier = Modifier.fillMaxWidth())
        } else {
            LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
        }

        Spacer(Modifier.height(16.dp))
        if (rows.isEmpty()) {
            Text(status?.describe() ?: "Connecting", style = quietBody)
        } else {
            SyncBreakdown(rows)
        }

        if (canBrowse) {
            Spacer(Modifier.height(24.dp))
            Button(onClick = onBrowseNow, modifier = Modifier.fillMaxWidth().height(52.dp)) {
                Text("Browse now", style = MaterialTheme.typography.labelLarge)
            }
            Spacer(Modifier.height(10.dp))
            Text(
                "The rest keeps arriving in the background.",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
        }
    }
}

/**
 * Artists, albums, songs, playlists — each with its state and its count.
 *
 * `.contain` rather than one merged label, matching iOS: every row speaks its
 * own state ("Albums, done"), and flattening them into a summary loses exactly
 * the detail the checklist exists to give.
 */
@Composable
private fun SyncBreakdown(rows: List<SyncPhaseRow>) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .semantics(mergeDescendants = false) { },
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        rows.forEach { row ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .semantics(mergeDescendants = true) {
                        contentDescription = "${row.label}, ${row.state}. ${row.countText}"
                    },
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(modifier = Modifier.size(18.dp), contentAlignment = Alignment.Center) {
                    when {
                        row.isDone -> Icon(
                            painterResource(R.drawable.ic_check),
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.size(14.dp),
                        )
                        row.isSyncing -> CircularProgressIndicator(
                            modifier = Modifier.size(12.dp),
                            strokeWidth = 1.5.dp,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        // A pending phase draws nothing. A greyed spinner on a
                        // row that has not started would read as four things
                        // running at once when only one ever is.
                        else -> Unit
                    }
                }
                Spacer(Modifier.width(10.dp))
                Text(
                    row.label,
                    style = MaterialTheme.typography.bodyMedium,
                    color = if (row.isDone || row.isSyncing) {
                        MaterialTheme.colorScheme.onSurface
                    } else {
                        MaterialTheme.colorScheme.onSurfaceVariant
                    },
                    modifier = Modifier.weight(1f),
                )
                Text(
                    row.countText,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
fun FailedScreen(message: String, canRetry: Boolean, onRetry: () -> Unit, onSignOut: () -> Unit) {
    OnboardingScaffold(title = "That did not work", subtitle = message) {
        if (canRetry) {
            Button(onClick = onRetry, modifier = Modifier.fillMaxWidth().height(52.dp)) {
                Text("Try again", style = MaterialTheme.typography.labelLarge)
            }
            Spacer(Modifier.height(12.dp))
        }
        OutlinedButton(onClick = onSignOut, modifier = Modifier.fillMaxWidth().height(52.dp)) {
            Text("Start over")
        }
    }
}

@Composable
fun StartingScreen() {
    Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
        Box(
            modifier = Modifier.fillMaxSize(),
            contentAlignment = Alignment.Center,
        ) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
            ) {
                Image(
                    painter = painterResource(R.drawable.mozz_logo),
                    contentDescription = null,
                    modifier = Modifier.size(72.dp),
                )
                Spacer(Modifier.height(14.dp))
                Text("Mozz", style = MaterialTheme.typography.displaySmall)
                Spacer(Modifier.height(24.dp))
                CircularProgressIndicator(
                    strokeWidth = 2.dp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

/**
 * A running scan, reported from inside the library rather than in front of it.
 *
 * The counterpart to [SyncingScreen], and the same checklist — but this one
 * sits in Home's scroll content, so it can cover nothing and scrolls away with
 * the rest of the page. It is what makes a resync background work: the library
 * stays where it is and this says what is happening to it.
 *
 * Mirrors iOS's `SyncStatusBar`, which has carried the same breakdown, the same
 * pacing and the same placement since it shipped.
 */
@Composable
fun SyncStatusCard(status: SyncStatus, modifier: Modifier = Modifier) {
    val smoother = remember { SyncProgressSmoother() }
    var rows by remember { mutableStateOf(emptyList<SyncPhaseRow>()) }
    LaunchedEffect(status) { rows = smoother.update(status) }
    LaunchedEffect(Unit) {
        while (true) {
            delay(250)
            rows = smoother.update(status)
        }
    }

    Surface(
        color = MaterialTheme.colorScheme.surfaceVariant,
        shape = MaterialTheme.shapes.large,
        border = if (LocalMozzBlackout.current) {
            BorderStroke(1.dp, MaterialTheme.colorScheme.outline)
        } else {
            null
        },
        modifier = modifier.fillMaxWidth(),
    ) {
        Column(Modifier.padding(horizontal = 14.dp, vertical = 13.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                CircularProgressIndicator(
                    modifier = Modifier.size(14.dp),
                    strokeWidth = 2.dp,
                    color = MaterialTheme.colorScheme.primary,
                )
                Spacer(Modifier.width(10.dp))
                Text(
                    "Syncing your library",
                    style = MaterialTheme.typography.titleSmall,
                    modifier = Modifier.weight(1f),
                )
            }
            val fraction = status.fraction
            Spacer(Modifier.height(11.dp))
            if (fraction != null) {
                LinearProgressIndicator(progress = { fraction }, modifier = Modifier.fillMaxWidth())
            } else {
                LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
            }
            Spacer(Modifier.height(12.dp))
            if (rows.isEmpty()) {
                Text(status.describe(), style = quietBody)
            } else {
                SyncBreakdown(rows)
            }
        }
    }
}
