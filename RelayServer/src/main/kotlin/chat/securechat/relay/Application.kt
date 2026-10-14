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
import org.slf4j.LoggerFactory
import redis.clients.jedis.JedisPooled
import java.util.UUID
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

fun Application.relayModule(config: Config, tokens: SessionTokens) {
    if (config.devClaimedAccounts) {
        logger.warn("RELAY_DEV_CLAIMED_ACCOUNTS is ON: any client can claim any account. Development only.")
    }
    val router = Router<DefaultWebSocketServerSession>()

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
            router.register(account, this)?.close(CloseReason(CloseReason.Codes.NORMAL, "replaced"))
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
                        runCatching { peer.send(Frame.Binary(true, Frames.fromSender(bytes, account))) }
                            .onFailure { send(Frame.Binary(true, Frames.peerUnavailable(destination))) }
                    }
                }
            } finally {
                router.unregister(account, this)
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
