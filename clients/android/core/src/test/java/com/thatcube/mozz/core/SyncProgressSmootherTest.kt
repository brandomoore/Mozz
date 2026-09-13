package com.thatcube.mozz.core

import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SyncProgressSmootherTest {

    private val json = Json { ignoreUnknownKeys = true }

    private fun status(vararg details: SyncPhaseDetail, running: Boolean = true, tracks: Int? = null) =
        SyncStatus(
            running = running,
            phase = details.firstOrNull { it.state == "syncing" }?.phase,
            itemsSynced = details.sumOf { it.synced },
            total = details.mapNotNull { it.total }.takeIf { it.isNotEmpty() }?.sum(),
            details = details.toList(),
            tracks = tracks,
        )

    private fun phase(name: String, state: String, synced: Int, total: Int? = null) =
        SyncPhaseDetail(name, name.replaceFirstChar { it.uppercase() }, state, synced, total, state == "done")

    /**
     * The first report is taken as read rather than counted up to.
     *
     * A sync resumed against a library already on the device opens at twenty
     * thousand songs, and easing from zero would spend a minute counting out
     * music that is already there.
     */
    @Test
    fun firstReportIsShownWhole() {
        val smoother = SyncProgressSmoother()
        val rows = smoother.update(status(phase("tracks", "syncing", 20_004, 20_004)), nowMillis = 0)

        assertEquals(1, rows.size)
        assertEquals(20_004, rows.single().synced)
    }

    /**
     * A page that lands all at once is walked up to, not jumped to.
     *
     * The core reports a page at a time, so a counter bound straight to it sits
     * still and then leaps — which reads as a stall followed by a glitch.
     */
    @Test
    fun aPageIsWalkedUpToRatherThanJumpedTo() {
        val smoother = SyncProgressSmoother()
        smoother.update(status(phase("tracks", "syncing", 0, 20_000)), nowMillis = 0)
        // A thousand songs arrive at once, ten seconds in.
        smoother.update(status(phase("tracks", "syncing", 1_000, 20_000)), nowMillis = 10_000)

        val partway = smoother.update(status(phase("tracks", "syncing", 1_000, 20_000)), nowMillis = 11_000)
            .single().synced
        assertTrue("should have moved off zero", partway > 0)
        assertTrue("should not have arrived in one second", partway < 1_000)

        // And it never overshoots what the server actually said.
        val later = smoother.update(status(phase("tracks", "syncing", 1_000, 20_000)), nowMillis = 60_000)
            .single().synced
        assertEquals(1_000, later)
    }

    /** A finished phase settles on its real count rather than easing toward it. */
    @Test
    fun aFinishedPhaseSettlesAtOnce() {
        val smoother = SyncProgressSmoother()
        smoother.update(status(phase("albums", "syncing", 0, 5_973)), nowMillis = 0)
        val rows = smoother.update(status(phase("albums", "done", 5_973, 5_973)), nowMillis = 1_000)

        assertEquals(5_973, rows.single().synced)
        assertTrue(rows.single().isDone)
    }

    /** Each phase is paced on its own; albums finishing must not drag songs along. */
    @Test
    fun phasesArePacedIndependently() {
        val smoother = SyncProgressSmoother()
        val first = status(phase("albums", "done", 5_973, 5_973), phase("tracks", "syncing", 0, 20_000))
        smoother.update(first, nowMillis = 0)
        smoother.update(
            status(phase("albums", "done", 5_973, 5_973), phase("tracks", "syncing", 8_000, 20_000)),
            nowMillis = 10_000,
        )
        val rows = smoother.update(
            status(phase("albums", "done", 5_973, 5_973), phase("tracks", "syncing", 8_000, 20_000)),
            nowMillis = 11_000,
        )

        assertEquals(5_973, rows[0].synced)
        assertTrue(rows[1].synced in 1..7_999)
    }

    /** A core that sends no breakdown still gets one row, so the view has one shape. */
    @Test
    fun noBreakdownStillYieldsARow() {
        val smoother = SyncProgressSmoother()
        val rows = smoother.update(
            SyncStatus(running = true, phase = "artists", phaseLabel = "Artists", itemsSynced = 12),
            nowMillis = 0,
        )

        assertEquals(listOf("Artists"), rows.map { it.label })
        assertEquals(12, rows.single().synced)
    }

    /** The counts read the way they are spoken, and an empty phase says so. */
    @Test
    fun countsReadTheWayTheyAreSpoken() {
        assertEquals("3,712 / 20,004", SyncPhaseRow("Songs", "syncing", 3_712, 20_004, false).countText)
        assertEquals("41", SyncPhaseRow("Playlists", "syncing", 41, null, false).countText)
        assertEquals("None", SyncPhaseRow("Playlists", "done", 0, 0, true).countText)
        assertEquals("", SyncPhaseRow("Playlists", "pending", 0, null, false).countText)
    }

    /**
     * The breakdown has to survive the wire.
     *
     * This is the actual bug: the core has always sent `details` and
     * `phaseLabel`, and Android's `SyncStatus` simply had no fields for them,
     * so they decoded into nothing and the app drew one unlabelled bar.
     */
    @Test
    fun theBreakdownDecodesFromTheCoresOwnShape() {
        val wire = """
            {"running":true,"finished":false,"phase":"tracks","phaseLabel":"Songs",
             "itemsSynced":3712,"total":20004,"tracks":3712,
             "details":[
               {"phase":"artists","label":"Artists","state":"done","synced":3004,"total":3004,"isComplete":true},
               {"phase":"tracks","label":"Songs","state":"syncing","synced":3712,"total":20004,"isComplete":false},
               {"phase":"playlists","label":"Playlists","state":"pending","synced":0,"isComplete":false}]}
        """.trimIndent()

        val status = json.decodeFromString<SyncStatus>(wire)

        assertEquals("Songs", status.phaseLabel)
        assertEquals(listOf("Artists", "Songs", "Playlists"), status.details.map { it.label })
        assertTrue(status.details[0].isComplete)
        assertTrue(status.details[1].isSyncing)
        assertTrue(status.details[2].isPending)
        assertNull(status.details[2].total)
    }

    /**
     * Whether there is enough to browse while the rest arrives.
     *
     * Android held people on a progress screen until the whole catalogue had
     * landed, which on a large Jellyfin library is several minutes with
     * thousands of songs already on the device. iOS has offered the way in
     * since it shipped.
     */
    @Test
    fun thereIsSomethingToShowOnceSongsStartLanding() {
        assertFalse(SyncStatus(running = true, tracks = 0).hasSomethingToShow)
        assertTrue(SyncStatus(running = true, tracks = 1).hasSomethingToShow)
        // Not while it is finished: that is Ready, not "browse early".
        assertFalse(SyncStatus(running = false, finished = true, tracks = 9_486).hasSomethingToShow)
    }

    @Test
    fun fractionIsClampedAndAbsentWithoutATotal() {
        assertNull(SyncStatus(running = true, itemsSynced = 10).fraction)
        assertEquals(0.5f, SyncStatus(running = true, itemsSynced = 5, total = 10).fraction!!, 0.0001f)
        assertEquals(1f, SyncStatus(running = true, itemsSynced = 50, total = 10).fraction!!, 0.0001f)
    }
}
