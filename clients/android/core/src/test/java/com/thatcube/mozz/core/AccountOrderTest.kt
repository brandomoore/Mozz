package com.thatcube.mozz.core

import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * First is active.
 *
 * The convention every client shares — the head of the accounts list is the
 * server being browsed — so this pins the ordering rules rather than the file
 * format. `saveAccount` used to append, which was invisible while only one
 * account could exist and wrong the moment a second could: a new sign-in went
 * to the back and the app carried on using the old server.
 *
 * Exercised against the ordering functions directly rather than through
 * MozzServer, which needs a keystore and a loaded native library.
 */
class AccountOrderTest {

    private fun account(id: String) = ServerAccount(
        serverId = id,
        kind = BackendKind.JELLYFIN,
        baseUrl = "https://$id.example.test",
        serverName = id,
        clientIdentifier = "client",
    )

    /** What `saveAccount` does to the list. */
    private fun save(accounts: List<ServerAccount>, new: ServerAccount) =
        listOf(new) + accounts.filterNot { it.serverId == new.serverId }

    /** What `makeActive` does to it. */
    private fun makeActive(accounts: List<ServerAccount>, serverId: String): List<ServerAccount> {
        val chosen = accounts.firstOrNull { it.serverId == serverId } ?: return accounts
        return listOf(chosen) + accounts.filterNot { it.serverId == serverId }
    }

    @Test
    fun aNewServerBecomesTheActiveOne() {
        val after = save(listOf(account("a")), account("b"))
        assertEquals(listOf("b", "a"), after.map { it.serverId })
    }

    @Test
    fun signingInAgainToTheSameServerReplacesItRatherThanListingItTwice() {
        var accounts = listOf(account("a"), account("b"))
        accounts = save(accounts, account("b").copy(serverName = "Renamed"))

        assertEquals(listOf("b", "a"), accounts.map { it.serverId })
        assertEquals("Renamed", accounts.first().serverName)
    }

    @Test
    fun switchingMovesTheChosenServerToTheFrontAndKeepsTheRest() {
        val accounts = listOf(account("a"), account("b"), account("c"))
        assertEquals(listOf("c", "a", "b"), makeActive(accounts, "c").map { it.serverId })
    }

    @Test
    fun switchingToAServerThatIsGoneChangesNothing() {
        val accounts = listOf(account("a"), account("b"))
        assertEquals(listOf("a", "b"), makeActive(accounts, "gone").map { it.serverId })
    }

    /**
     * The accounts file is plain JSON and is read back by every launch; an
     * account written by this build has to decode in the next one.
     */
    @Test
    fun anAccountSurvivesTheRoundTrip() {
        val json = Json { ignoreUnknownKeys = true }
        val encoded = json.encodeToString(listOf(account("a"), account("b")))
        val decoded = json.decodeFromString<List<ServerAccount>>(encoded)

        assertEquals(listOf("a", "b"), decoded.map { it.serverId })
        assertEquals(BackendKind.JELLYFIN, decoded.first().kind)
    }
}
