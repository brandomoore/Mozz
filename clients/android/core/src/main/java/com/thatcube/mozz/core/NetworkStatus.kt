package com.thatcube.mozz.core

import java.net.NetworkInterface
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable

@Serializable
data class NetworkInterfaceSnapshot(
    val name: String,
    val isUp: Boolean,
    val isLoopback: Boolean,
    val addresses: List<String>,
)

@Serializable
data class TailscaleNetwork(val detected: Boolean)

/** Enumerate only; the shared Swift core decides what indicates Tailscale. */
internal suspend fun networkInterfaces(): List<NetworkInterfaceSnapshot> = withContext(Dispatchers.IO) {
    NetworkInterface.getNetworkInterfaces()?.toList().orEmpty().map { network ->
        NetworkInterfaceSnapshot(
            name = network.name,
            isUp = network.isUp,
            isLoopback = network.isLoopback,
            addresses = network.inetAddresses.toList().mapNotNull { it.hostAddress },
        )
    }
}
