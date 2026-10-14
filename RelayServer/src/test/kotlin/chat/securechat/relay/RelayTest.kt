package chat.securechat.relay

import io.ktor.client.plugins.websocket.DefaultClientWebSocketSession
import io.ktor.client.plugins.websocket.WebSockets
import io.ktor.client.plugins.websocket.webSocket
import io.ktor.client.request.header
import io.ktor.server.testing.ApplicationTestBuilder
import io.ktor.server.testing.testApplication
import io.ktor.websocket.CloseReason
import io.ktor.websocket.Frame
import io.ktor.websocket.readBytes
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeout
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertNull

class RelayTest {

    private val ada: UUID = UUID.randomUUID()
    private val bob: UUID = UUID.randomUUID()
    private val adaToken = "token-ada"

    private fun ApplicationTestBuilder.relay(devClaimedAccounts: Boolean = true) {
        application {
            relayModule(Config(port = 0, redisUrl = "", devClaimedAccounts = devClaimedAccounts),
                        tokens = { token -> if (token == adaToken) ada else null })
        }
    }

    private fun deliver(to: UUID, marker: Byte): ByteArray =
        ByteArray(Frames.SIZE).also {
            it[0] = Frames.VERSION
            it[1] = Frames.KIND_DELIVER
            Frames.bytes(to).copyInto(it, 2)
            it[100] = marker
        }

    private suspend fun DefaultClientWebSocketSession.nextBinary(): ByteArray =
        withTimeout(5_000) {
            while (true) {
                val frame = incoming.receive()
                if (frame is Frame.Binary) return@withTimeout frame.readBytes()
            }
            @Suppress("UNREACHABLE_CODE") ByteArray(0)
        }

    private suspend fun DefaultClientWebSocketSession.closeReason(): CloseReason? =
        withTimeout(5_000) { closeReason.await() }

    @Test
    fun `a frame reaches the addressed peer, naming the sender, body untouched`() = testApplication {
        relay()
        val client = createClient { install(WebSockets) }
        coroutineScope {
            val bobReady = CompletableDeferred<Unit>()
            val received = CompletableDeferred<ByteArray>()
            launch {
                client.webSocket("/relay", request = { header("X-Dev-Account", bob.toString()) }) {
                    // A round trip proves Bob is registered before Ada sends.
                    send(Frame.Binary(true, deliver(UUID.randomUUID(), 0)))
                    nextBinary()
                    bobReady.complete(Unit)
                    received.complete(nextBinary())
                }
            }
            bobReady.await()
            client.webSocket("/relay", request = { header("Authorization", "Bearer $adaToken") }) {
                send(Frame.Binary(true, deliver(bob, 42)))
                received.await()
            }
            val frame = received.await()
            assertEquals(Frames.SIZE, frame.size)
            assertEquals(Frames.KIND_DELIVER, frame[1])
            assertContentEquals(Frames.bytes(ada), frame.copyOfRange(2, 18))
            assertEquals(42, frame[100].toInt())
        }
    }

    @Test
    fun `a frame for someone not connected gets peer unavailable back`() = testApplication {
        relay()
        createClient { install(WebSockets) }
            .webSocket("/relay", request = { header("X-Dev-Account", ada.toString()) }) {
                send(Frame.Binary(true, deliver(bob, 1)))
                val reply = nextBinary()
                assertEquals(Frames.SIZE, reply.size)
                assertEquals(Frames.KIND_PEER_UNAVAILABLE, reply[1])
                assertContentEquals(Frames.bytes(bob), reply.copyOfRange(2, 18))
            }
    }

    @Test
    fun `a frame of the wrong size closes the connection`() = testApplication {
        relay()
        createClient { install(WebSockets) }
            .webSocket("/relay", request = { header("X-Dev-Account", ada.toString()) }) {
                send(Frame.Binary(true, deliver(bob, 1).copyOf(100)))
                assertEquals(CloseReason.Codes.VIOLATED_POLICY.code, closeReason()?.code)
            }
    }

    @Test
    fun `no credentials, or a claimed account with the dev flag off, is refused`() = testApplication {
        relay(devClaimedAccounts = false)
        val client = createClient { install(WebSockets) }
        client.webSocket("/relay") {
            assertEquals(CloseReason.Codes.VIOLATED_POLICY.code, closeReason()?.code)
        }
        client.webSocket("/relay", request = { header("X-Dev-Account", ada.toString()) }) {
            assertEquals(CloseReason.Codes.VIOLATED_POLICY.code, closeReason()?.code)
        }
        client.webSocket("/relay", request = { header("Authorization", "Bearer wrong") }) {
            assertEquals(CloseReason.Codes.VIOLATED_POLICY.code, closeReason()?.code)
        }
    }

    @Test
    fun `authenticate prefers a token and only honours a claimed account in dev mode`() {
        val tokens = SessionTokens { if (it == adaToken) ada else null }
        val dev = Config(0, "", devClaimedAccounts = true)
        val prod = Config(0, "", devClaimedAccounts = false)
        assertEquals(ada, authenticate("Bearer $adaToken", bob.toString(), dev, tokens))
        assertEquals(bob, authenticate(null, bob.toString(), dev, tokens))
        assertNull(authenticate(null, bob.toString(), prod, tokens))
        assertNull(authenticate(adaToken, null, prod, tokens), "a token without the Bearer prefix")
        assertNull(authenticate(null, "not-a-uuid", dev, tokens))
    }
}
