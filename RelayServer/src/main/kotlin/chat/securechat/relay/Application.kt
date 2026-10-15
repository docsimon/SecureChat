package chat.securechat.relay

import io.ktor.server.application.Application
import io.ktor.server.application.install
import io.ktor.server.engine.embeddedServer
import io.ktor.server.netty.Netty
import io.ktor.server.request.header
import io.ktor.server.routing.routing
import io.ktor.server.websocket.DefaultWebSocketServerSession
import io.ktor.server.websocket.WebSockets
import io.ktor.server.websocket.pingPeriod
import io.ktor.server.websocket.timeout
import io.ktor.server.websocket.webSocket
import io.ktor.websocket.CloseReason
import io.ktor.websocket.Frame
import io.ktor.websocket.close
import io.ktor.websocket.readBytes
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext
import org.slf4j.LoggerFactory
import redis.clients.jedis.JedisPooled
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import kotlin.time.Duration.Companion.seconds

private val logger = LoggerFactory.getLogger("chat.securechat.relay.Application")

fun main() {
    val config = Config.fromEnv()
    val redis = JedisPooled(config.redisUrl)
    embeddedServer(Netty, port = config.port, module = {
        relayModule(config, tokens = RedisSessionTokens(redis))
    }).start(wait = true)
}

/** Looks a session token up. The Auth Server issues them (`POST /session`). */
fun interface SessionTokens {
    fun accountFor(token: String): UUID?
}

/** Same key layout as the Auth Server's `SessionTokenStore`. */
class RedisSessionTokens(private val redis: JedisPooled) : SessionTokens {
    override fun accountFor(token: String): UUID? =
        redis.get("session:token:$token")?.let { runCatching { UUID.fromString(it) }.getOrNull() }
}

/**
 * One open connection and who it has talked with, in memory, gone with it
 * (architecture-decisions.md §1: routing state is deleted on disconnect).
 */
internal class Client(val session: DefaultWebSocketServerSession, val account: UUID) {
    /** Accounts this connection delivered frames to. */
    val sentTo: MutableSet<UUID> = ConcurrentHashMap.newKeySet()
    /** Accounts whose frames were delivered to this connection. */
    val receivedFrom: MutableSet<UUID> = ConcurrentHashMap.newKeySet()

    /**
     * Who is told when this connection closes: frames went both ways.
     * Someone who only wrote to us (a stranger, a contact we removed and
     * so ignore) learns nothing about our leaving.
     */
    fun conversations(): Set<UUID> = sentTo intersect receivedFrom
}

fun Application.relayModule(config: Config, tokens: SessionTokens) {
    if (config.devClaimedAccounts) {
        logger.warn("RELAY_DEV_CLAIMED_ACCOUNTS is ON: any client can claim any account. Development only.")
    }
    val router = Router<Client>()

    install(WebSockets) {
        pingPeriod = 30.seconds
        timeout = 60.seconds
        // Anything larger is refused before it is buffered (§5).
        maxFrameSize = Frames.SIZE.toLong()
    }

    routing {
        webSocket("/relay") {
            val account = authenticate(call.request.header("Authorization"),
                                       call.request.header("X-Dev-Account"), config, tokens)
            if (account == null) {
                close(CloseReason(CloseReason.Codes.VIOLATED_POLICY, "unauthorized"))
                return@webSocket
            }
            val client = Client(this, account)
            router.register(account, client)?.session?.close(CloseReason(CloseReason.Codes.NORMAL, "replaced"))
            logger.info("Connected ({} online)", router.size)
            try {
                for (frame in incoming) {
                    if (frame !is Frame.Binary) continue
                    val bytes = frame.readBytes()
                    val destination = Frames.destination(bytes)
                    if (destination == null) {
                        close(CloseReason(CloseReason.Codes.VIOLATED_POLICY, "bad frame"))
                        break
                    }
                    val peer = router.connection(destination)
                    if (peer == null) {
                        send(Frame.Binary(true, Frames.peerUnavailable(destination)))
                    } else {
                        // A peer that just went away is the same as one that is offline.
                        runCatching { peer.session.send(Frame.Binary(true, Frames.fromSender(bytes, account))) }
                            .onSuccess {
                                client.sentTo.add(destination)
                                peer.receivedFrom.add(account)
                            }
                            .onFailure { send(Frame.Binary(true, Frames.peerUnavailable(destination))) }
                    }
                }
            } finally {
                router.unregister(account, client)
                // "Contact left" (session-workflow.md, "Presence"): the same
                // frame as for an offline peer, unasked. Their app drops its
                // session with us and shows us offline. Also on "replaced":
                // the sessions of this connection are gone either way.
                withContext(NonCancellable) {
                    for (other in client.conversations()) {
                        val peer = router.connection(other) ?: continue
                        runCatching { peer.session.send(Frame.Binary(true, Frames.peerUnavailable(account))) }
                    }
                }
                logger.info("Disconnected ({} online)", router.size)
            }
        }
    }
}

internal fun authenticate(authorization: String?, devAccount: String?, config: Config, tokens: SessionTokens): UUID? {
    val token = authorization?.removePrefix("Bearer ")?.takeIf { it != authorization && it.isNotBlank() }
    if (token != null) return tokens.accountFor(token)
    if (config.devClaimedAccounts && devAccount != null) {
        return runCatching { UUID.fromString(devAccount) }.getOrNull()
    }
    return null
}
