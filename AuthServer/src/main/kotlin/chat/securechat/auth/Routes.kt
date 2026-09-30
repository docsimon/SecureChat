package chat.securechat.auth

import io.ktor.http.HttpStatusCode
import io.ktor.server.application.call
import io.ktor.server.request.receive
import io.ktor.server.response.respond
import io.ktor.server.routing.Routing
import io.ktor.server.routing.get
import io.ktor.server.routing.post
import kotlinx.serialization.Serializable
import java.util.Base64
import java.util.UUID

// Standard base64 (with padding), not URL-safe: `keyId` comes straight from
// DCAppAttestService.generateKey() as standard base64 and the app doesn't
// re-encode it, so the server has to speak the same dialect for every field
// on this wire, not just keyId, to avoid mixing encodings per-field.
private val base64 = Base64.getEncoder()
private fun String.decodeBase64(): ByteArray = Base64.getDecoder().decode(this)

@Serializable
data class ChallengeResponse(val challenge: String)

@Serializable
data class RegisterRequest(
    val keyId: String,
    val challenge: String,
    val attestation: String,
    val identityPublicKey: String,
)

@Serializable
data class RegisterResponse(val accountUuid: String)

@Serializable
data class SessionRequest(
    // NOT keyId — deliberately. AssertionSigning.sign(_:) never exposes keyId
    // to the app (by module design), so the app can never supply it here.
    // account_uuid is what the app is actually meant to hold onto after
    // registration (architecture-decisions.md: "Client stores the UUID").
    val accountUuid: String,
    val assertion: String,
    val nonce: String,
    val body: String,
)

@Serializable
data class SessionResponse(val sessionToken: String, val accountUuid: String)

fun Routing.authRoutes(
    registrationChallenges: RegistrationChallengeStore,
    sessionNonces: SessionNonceStore,
    sessionTokens: SessionTokenStore,
    accounts: AccountRepository,
    verification: AppAttestVerification,
) {
    get("/challenge") {
        val identityPublicKey = call.request.queryParameters["identityPublicKey"]
            ?: badRequest("identity_public_key_required")
        val challenge = registrationChallenges.issue(identityPublicKey)
        call.respond(ChallengeResponse(base64.encodeToString(challenge)))
    }

    post("/register") {
        val request = call.receive<RegisterRequest>()
        val keyId = request.keyId.decodeBase64()

        // Idempotency check MUST come before consuming the challenge: a
        // client retrying after a lost response resubmits the same cached
        // challenge (module doc §7a/§8 — attestation is cached client-side
        // and the retry "skips Apple entirely"). If we consumed the
        // single-use challenge on the first attempt, the retry would see
        // challenge_invalid_or_expired instead of the idempotent success
        // architecture-decisions.md §6 requires.
        accounts.findByKeyId(keyId)?.let { existing ->
            call.respond(RegisterResponse(existing.accountUuid.toString()))
            return@post
        }

        val challengeBytes = request.challenge.decodeBase64()

        val boundIdentityKey = registrationChallenges.consume(challengeBytes)
            ?: badRequest("challenge_invalid_or_expired")

        // The identity binding that used to live inside clientDataHash lives
        // here now (account-keys-reference.md) — the attestation proves "a
        // genuine app attested THIS challenge"; this proves "and the caller
        // asking to register is the same one who fetched that challenge."
        if (boundIdentityKey != request.identityPublicKey) {
            badRequest("identity_mismatch")
        }

        val validated = try {
            verification.validateAttestation(
                attestationObject = request.attestation.decodeBase64(),
                keyIdBase64 = request.keyId,
                challenge = challengeBytes,
            )
        } catch (e: Exception) {
            // Not just AttestationException: malformed CBOR fails inside
            // Jackson before the library's own validation even starts, and
            // that's a client input problem too — a raw parser exception
            // must never reach the client as an unhandled 500 (caught a real
            // one of these while smoke-testing: leaked a Jackson message).
            badRequest("attestation_invalid:${e::class.simpleName}")
        }

        val account = accounts.registerOrReturnExisting(
            keyId = keyId,
            attestPublicKey = validated.certificate.publicKey as java.security.interfaces.ECPublicKey,
        )
        call.respond(RegisterResponse(account.accountUuid.toString()))
    }

    get("/session/nonce") {
        val nonce = sessionNonces.issue()
        call.respond(ChallengeResponse(base64.encodeToString(nonce)))
    }

    post("/session") {
        val request = call.receive<SessionRequest>()
        val nonceBytes = request.nonce.decodeBase64()

        if (!sessionNonces.consume(nonceBytes)) {
            badRequest("nonce_invalid_or_expired")
        }

        val account = accounts.findByAccountUuid(UUID.fromString(request.accountUuid))
            ?: notFound("unknown_account")

        val bodyBytes = request.body.decodeBase64()
        val clientData = nonceBytes + bodyBytes

        val assertion = try {
            verification.validateAssertion(
                assertionObject = request.assertion.decodeBase64(),
                clientData = clientData,
                attestationPublicKey = account.attestPublicKey,
                lastCounter = account.counter,
                nonce = nonceBytes,
            )
        } catch (e: Exception) {
            // Same reasoning as /register's catch: malformed CBOR fails
            // before AssertionException is ever thrown.
            unauthorized("assertion_invalid:${e::class.simpleName}")
        }

        val newCounter = assertion.authenticatorData.signCount
        if (!accounts.advanceCounter(account.keyId, account.counter, newCounter)) {
            // Another request for the same key won the race in between our
            // read and write. Reject rather than silently accept a stale
            // counter transition.
            unauthorized("counter_conflict")
        }

        val token = sessionTokens.issue(account.accountUuid)
        call.respond(SessionResponse(sessionToken = token, accountUuid = account.accountUuid.toString()))
    }
}
