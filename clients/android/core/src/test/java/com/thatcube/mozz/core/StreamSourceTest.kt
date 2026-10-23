package com.thatcube.mozz.core

import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class StreamSourceTest {
    @Test
    fun preservesBackendAuthenticationHeaders() {
        val source = Json.decodeFromString<StreamSource>(
            """{"url":"https://example.test/audio","headers":{"Authorization":"MediaBrowser Token=\"test-only\""}}"""
        )
        assertEquals("MediaBrowser Token=\"test-only\"", source.headers["Authorization"])
    }

    @Test
    fun olderBackendsWithoutHeadersRemainCompatible() {
        val source = Json.decodeFromString<StreamSource>("""{"url":"https://example.test/audio"}""")
        assertTrue(source.headers.isEmpty())
    }
}
