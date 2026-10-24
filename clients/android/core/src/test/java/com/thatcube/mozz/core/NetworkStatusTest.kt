package com.thatcube.mozz.core

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class NetworkStatusTest {
    @Test
    fun interfaceSnapshotMatchesTheSharedWireContract() {
        val request = CoreRequest(
            cmd = "networkStatus",
            networkInterfaces = listOf(NetworkInterfaceSnapshot("tun0", true, false, listOf("100.100.10.20"))),
        )
        val json = Json.parseToJsonElement(Json.encodeToString(CoreRequest.serializer(), request)).jsonObject
        val item = json["networkInterfaces"]!!.jsonArray[0].jsonObject
        assertEquals("tun0", item["name"]!!.jsonPrimitive.content)
        assertEquals("true", item["isUp"]!!.jsonPrimitive.content)
        assertEquals("false", item["isLoopback"]!!.jsonPrimitive.content)
        assertEquals("100.100.10.20", item["addresses"]!!.jsonArray[0].jsonPrimitive.content)
        assertTrue(Json.decodeFromString<TailscaleNetwork>("""{"detected":true}""").detected)
    }
}
