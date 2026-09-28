package chat.securechat.auth

import io.ktor.http.HttpStatusCode
import io.ktor.serialization.kotlinx.json.json
import io.ktor.server.application.Application
import io.ktor.server.application.call
import io.ktor.server.application.install
import io.ktor.server.engine.embeddedServer
import io.ktor.server.netty.Netty
import io.ktor.server.plugins.PayloadTooLargeException
import io.ktor.server.plugins.bodylimit.RequestBodyLimit
import io.ktor.server.plugins.calllogging.CallLogging
import io.ktor.server.plugins.contentnegotiation.ContentNegotiation
import io.ktor.server.plugins.statuspages.StatusPages
import io.ktor.server.response.respond
import io.ktor.server.routing.routing
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import org.slf4j.LoggerFactory
import redis.clients.jedis.JedisPooled

fun main() {
    val config = Config.fromEnv()
    embeddedServer(Netty, port = config.port, module = { module(config) }).start(wait = true)
}

@Serializable
private data class ErrorResponse(val error: String)

private val logger = LoggerFactory.getLogger("chat.securechat.auth.Application")

fun Application.module(config: Config) {
    val redis = JedisPooled(config.redisUrl)
    val dataSource = AccountRepository.createDataSource(config)
    val accounts = AccountRepository(dataSource).also { it.migrate() }
    val verification = AppAttestVerification(config)

    // Real payloads here are tiny — an attestation object is ~5KB of CBOR
    // (module doc), base64'd to ~7KB; everything else is a few hundred
    // bytes. 256 KB is generous headroom, not a tuned limit, but without
    // ANY limit Ktor buffers and fully parses arbitrarily large bodies —
    // confirmed with a real 50MB request during this session's security
    // review: it took 542ms of real CPU/memory work before failing for an
    // unrelated reason. Installed before ContentNegotiation so an oversized
    // body is rejected before any JSON/base64 work starts on it.
    install(RequestBodyLimit) { bodyLimit { 256 * 1024 } }
    install(ContentNegotiation) { json(Json { ignoreUnknownKeys = true }) }
    install(CallLogging)
    install(StatusPages) {
        exception<ApiException> { call, cause ->
            call.respond(cause.status, ErrorResponse(cause.code))
        }
        // Unparseable/wrong-shaped request body is a client error, not a
        // server fault — Ktor throws this from ContentNegotiation before a
        // route body even runs, so it would otherwise fall into the
        // Throwable catch-all below as a misleading 500.
        exception<io.ktor.server.plugins.BadRequestException> { call, _ ->
            call.respond(HttpStatusCode.BadRequest, ErrorResponse("malformed_request"))
        }
        // Same reasoning, different failure point: a field that isn't valid
        // base64 at all (keyId, challenge, attestation, nonce, body,
        // assertion — every one of them decodes via Base64.getDecoder() in
        // Routes.kt) throws IllegalArgumentException before any route logic
        // runs. Confirmed as a real bug via curl before this existed: it fell
        // through to the Throwable catch-all as a 500, for what is plainly a
        // 400. Deliberately not scoped to Routes.kt's own decode calls —
        // this is a request-shape problem, same tier as BadRequestException.
        exception<IllegalArgumentException> { call, _ ->
            call.respond(HttpStatusCode.BadRequest, ErrorResponse("malformed_request"))
        }
        exception<PayloadTooLargeException> { call, _ ->
            call.respond(HttpStatusCode.PayloadTooLarge, ErrorResponse("payload_too_large"))
        }
        // Safety net: an unanticipated exception anywhere else (bad JSON
        // body, a Redis/DB hiccup, ...) must never leak an internal message
        // to the client — caught a real instance of exactly this while
        // smoke-testing /register with malformed CBOR before this existed.
        exception<Throwable> { call, cause ->
            logger.error("Unhandled exception", cause)
            call.respond(HttpStatusCode.InternalServerError, ErrorResponse("internal_error"))
        }
    }

    routing {
        authRoutes(
            registrationChallenges = RegistrationChallengeStore(redis),
            sessionNonces = SessionNonceStore(redis),
            sessionTokens = SessionTokenStore(redis),
            accounts = accounts,
            verification = verification,
        )
    }
}
