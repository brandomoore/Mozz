package com.thatcube.mozz.playback

import java.net.HttpURLConnection
import java.net.URI
import kotlin.concurrent.thread

/**
 * Opens a connection to the server before anything needs one.
 *
 * On a cold start the first play's wait is mostly setup — DNS, TCP and TLS to a
 * server nothing has spoken to yet — and once one connection exists, songs
 * start promptly. So a connection is opened ahead of the first play, at launch
 * and whenever the app comes back to the foreground, as the iPhone and desktop
 * apps do.
 *
 * Through `HttpURLConnection` on purpose: ExoPlayer's default HTTP source is
 * built on it, and the platform keeps one keep-alive pool for the process, so a
 * connection opened here is the one the stream reuses. A warm connection in any
 * other client — the artwork OkHttp client, say — would not be.
 *
 * A HEAD with no credentials: the answer does not matter (a 401 warms the
 * connection as well as a 200), and sending nothing means nothing sensitive
 * goes anywhere. The response is read and the connection left open rather than
 * disconnected, because `disconnect()` closes the socket instead of returning
 * it to the pool — which would undo the whole point. At most once every 30
 * seconds per server, on a background thread, and it never throws.
 */
object ServerPrewarm {
    private const val THROTTLE_MS = 30_000L
    private const val TIMEOUT_MS = 10_000
    private val lastPrewarm = HashMap<String, Long>()

    /** Warm [baseUrl]'s server. Returns whether a request was started. */
    fun prewarm(baseUrl: String?, now: Long = System.currentTimeMillis()): Boolean {
        val uri = baseUrl?.let { runCatching { URI(it) }.getOrNull() } ?: return false
        if (uri.scheme != "http" && uri.scheme != "https") return false
        val server = "${uri.scheme}://${uri.authority}"
        synchronized(lastPrewarm) {
            val last = lastPrewarm[server]
            if (last != null && now - last < THROTTLE_MS) return false
            lastPrewarm[server] = now
        }
        thread(name = "mozz-prewarm", isDaemon = true) {
            runCatching {
                val connection = uri.toURL().openConnection() as HttpURLConnection
                connection.requestMethod = "HEAD"
                connection.connectTimeout = TIMEOUT_MS
                connection.readTimeout = TIMEOUT_MS
                val code = connection.responseCode
                // Consuming the (empty) body is what hands the socket back to the pool.
                (if (code >= 400) connection.errorStream else connection.inputStream)?.close()
            }
        }
        return true
    }
}
