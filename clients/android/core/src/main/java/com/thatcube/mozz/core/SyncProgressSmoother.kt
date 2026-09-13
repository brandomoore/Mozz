package com.thatcube.mozz.core

/**
 * Walks the sync counters up to each new page instead of letting them jump.
 *
 * The core reports a page at a time — a thousand songs arrive as one number, a
 * dozen seconds apart — so a counter bound straight to it sits perfectly still
 * and then leaps, which reads as a stall followed by a glitch rather than as
 * work being done. This paces the displayed number toward the reported one at
 * roughly the rate the pages have actually been arriving, so a slow sync still
 * looks like it is moving without ever claiming a number the server has not
 * confirmed.
 *
 * The constants are the ones in the desktop's `SyncProgressSmoother` and iOS's,
 * deliberately: the same library syncing on a phone and a laptop side by side
 * has to count at the same speed, or one of the two looks broken.
 *
 * It never overshoots. [SyncCounterPacer.advance] clamps to the reported total,
 * so the displayed figure is always one the server has already sent.
 */
class SyncProgressSmoother {
    private val pacers = mutableMapOf<String, SyncCounterPacer>()
    private var lastUpdate: Long? = null

    /** Drop everything, for when a sync finishes or a different server starts one. */
    fun reset() {
        pacers.clear()
        lastUpdate = null
    }

    /**
     * @param nowMillis injectable so the tests can drive time rather than sleep.
     */
    fun update(status: SyncStatus?, nowMillis: Long = System.currentTimeMillis()): List<SyncPhaseRow> {
        if (status == null) return emptyList()

        val elapsed = lastUpdate?.let { ((nowMillis - it).coerceAtLeast(0L)) / 1000.0 } ?: 0.0
        lastUpdate = nowMillis

        // A core that sent no breakdown still gets one row, so the view has one
        // shape to draw rather than two.
        val details = status.details.ifEmpty {
            listOf(
                SyncPhaseDetail(
                    phase = status.phase ?: "syncing",
                    label = status.phaseLabel ?: "Syncing",
                    state = if (status.finished) "done" else "syncing",
                    synced = status.itemsSynced,
                    total = status.total,
                    isComplete = status.finished,
                )
            )
        }

        return details.map { detail ->
            val pacer = pacers.getOrPut(detail.phase) { SyncCounterPacer() }
            if (detail.state == "done" || detail.isComplete) pacer.settle(detail.synced)
            else pacer.report(detail.synced, nowMillis)
            if (elapsed > 0) pacer.advance(elapsed)
            SyncPhaseRow(detail.label, detail.state, pacer.displayed, detail.total, detail.isComplete)
        }
    }
}

/** One phase's line, with the paced count rather than the raw one. */
data class SyncPhaseRow(
    val label: String,
    val state: String,
    val synced: Int,
    val total: Int?,
    val isComplete: Boolean,
) {
    val isDone: Boolean get() = state == "done" || isComplete
    val isSyncing: Boolean get() = state == "syncing"

    val countText: String
        get() = when {
            isDone && synced == 0 -> "None"
            state == "pending" && synced == 0 && (total ?: 0) == 0 -> ""
            (total ?: 0) > 0 -> "%,d / %,d".format(synced, total)
            else -> "%,d".format(synced)
        }
}

/** One counter's easing. See [SyncProgressSmoother] for why this exists. */
class SyncCounterPacer {
    private var position = 0.0
    private var target = 0.0

    /** How far apart the pages have been arriving, in seconds. */
    private var pageInterval = 15.0
    private var lastArrival: Long? = null
    private var seeded = false

    val displayed: Int get() = kotlin.math.floor(position).toInt()

    fun report(count: Int, nowMillis: Long) {
        val value = count.toDouble()
        if (!seeded) {
            // The first number is the truth, not something to walk up to: easing
            // from zero on a resumed sync would count out a library that is
            // already there.
            position = value
            target = value
            lastArrival = nowMillis
            seeded = true
            return
        }
        if (kotlin.math.abs(value - target) < 0.001) return
        if (value > target) {
            lastArrival?.let { last ->
                val elapsed = (nowMillis - last) / 1000.0
                // Bounds either side: under a quarter second is two reports of
                // the same page, over five minutes is a sleeping device, and
                // neither says anything about how fast this sync is going.
                if (elapsed > 0.25 && elapsed < 300) {
                    pageInterval = pageInterval * 0.6 + elapsed * 0.4
                }
            }
            lastArrival = nowMillis
        }
        target = value
        // A count that went backwards (a fresh sync of the same phase) is
        // followed down rather than waited out.
        if (position > target) position = target
    }

    fun settle(count: Int) {
        position = count.toDouble()
        target = count.toDouble()
        seeded = true
    }

    /** @return whether there is still ground to cover. */
    fun advance(elapsedSeconds: Double): Boolean {
        if (position >= target) {
            position = kotlin.math.min(position, target)
            return false
        }
        val spread = (pageInterval * STRETCH).coerceIn(MINIMUM_SPREAD, MAXIMUM_SPREAD)
        val gap = target - position
        val rate = kotlin.math.max(gap / spread, MINIMUM_RATE)
        position = kotlin.math.min(position + rate * elapsedSeconds, target)
        return position < target
    }

    private companion object {
        /** Aim to arrive slightly after the next page, not before it. */
        const val STRETCH = 1.25
        const val MINIMUM_SPREAD = 4.0
        const val MAXIMUM_SPREAD = 60.0

        /** Never fully stop: a counter that stands still reads as a hang. */
        const val MINIMUM_RATE = 0.8
    }
}
