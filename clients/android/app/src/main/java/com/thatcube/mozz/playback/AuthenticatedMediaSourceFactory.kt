package com.thatcube.mozz.playback

import android.content.Context
import android.os.Bundle
import androidx.media3.common.MediaItem
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.drm.DrmSessionManagerProvider
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.source.MediaSource
import androidx.media3.exoplayer.upstream.LoadErrorHandlingPolicy

private const val STREAM_HEADERS = "mozz.streamHeaders"

/** Request metadata survives the controller-to-service boundary; local tags do not. */
internal fun MediaItem.Builder.setStreamRequest(
    url: String,
    headers: Map<String, String>,
): MediaItem.Builder {
    val values = Bundle().apply { headers.forEach { (name, value) -> putString(name, value) } }
    val extras = Bundle().apply { putBundle(STREAM_HEADERS, values) }
    return setUri(url).setRequestMetadata(MediaItem.RequestMetadata.Builder().setExtras(extras).build())
}

/** Each media source gets its own headers, including lookahead and Android Auto items. */
internal class AuthenticatedMediaSourceFactory(private val context: Context) : MediaSource.Factory {
    private val factory = DefaultMediaSourceFactory(context)

    override fun createMediaSource(mediaItem: MediaItem): MediaSource {
        val values = mediaItem.requestMetadata.extras?.getBundle(STREAM_HEADERS)
        val headers = values?.keySet()?.mapNotNull { name ->
            values.getString(name)?.let { name to it }
        }?.toMap().orEmpty()
        val http = DefaultHttpDataSource.Factory().setDefaultRequestProperties(headers)
        return factory.setDataSourceFactory(DefaultDataSource.Factory(context, http))
            .createMediaSource(mediaItem)
    }

    override fun getSupportedTypes(): IntArray = factory.supportedTypes

    override fun setDrmSessionManagerProvider(provider: DrmSessionManagerProvider): MediaSource.Factory {
        factory.setDrmSessionManagerProvider(provider)
        return this
    }

    override fun setLoadErrorHandlingPolicy(policy: LoadErrorHandlingPolicy): MediaSource.Factory {
        factory.setLoadErrorHandlingPolicy(policy)
        return this
    }
}
