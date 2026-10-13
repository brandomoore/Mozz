package com.thatcube.mozz.playback

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ServerPrewarmTest {
    // 127.0.0.1:9 refuses at once, so the background request ends quickly and
    // touches nothing outside the machine. Unique paths do not matter: the
    // throttle is per server, scheme and authority.
    private fun server(port: Int) = "http://127.0.0.1:$port"

    @Test
    fun aServerIsWarmedOnceThenLeftAloneForThirtySeconds() {
        val base = server(9)
        val start = 1_000_000L
        assertTrue(ServerPrewarm.prewarm(base, now = start))
        assertFalse(
            "every return to the foreground asks; only one in thirty seconds goes",
            ServerPrewarm.prewarm("$base/library/sections", now = start + 29_000),
        )
        assertTrue(ServerPrewarm.prewarm(base, now = start + 30_001))
    }

    @Test
    fun differentServersAreWarmedIndependently() {
        val now = 5_000_000L
        assertTrue(ServerPrewarm.prewarm(server(19), now = now))
        assertTrue(ServerPrewarm.prewarm(server(29), now = now))
    }

    @Test
    fun anythingThatIsNotAWebServerIsIgnored() {
        listOf(null, "", "file:///music", "not a url", "ftp://host/x").forEach {
            assertFalse("should ignore $it", ServerPrewarm.prewarm(it))
        }
    }
}
