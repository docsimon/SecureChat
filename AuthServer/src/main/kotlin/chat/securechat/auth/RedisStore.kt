package chat.securechat.auth

import redis.clients.jedis.JedisPooled
import java.security.SecureRandom
import java.time.Duration
import java.util.Base64
import java.util.UUID

private val secureRandom = SecureRandom()
// Standard base64, matching Routes.kt — see the comment there for why the
// whole wire protocol uses one encoding rather than mixing per field.
private val base64 = Base64.getEncoder()

private fun randomBytes(count: Int): ByteArray = ByteArray(count).also(secureRandom::nextBytes)

/**
 * Registration challenges. TTL is 15 minutes, not the session nonce's 60s
 * — a cached attestation can resume against this challenge and the key can
 * only be attested once (module doc §7a; see architecture-decisions.md,
 * fixed there after it drifted out of sync with this reasoning).
 *
 * Also carries the identity binding that used to live inside clientDataHash:
 * the challenge is stored keyed to the identityPublicKey that requested it,
 * and /register must confirm the two still match (account-keys-reference.md).
 */
class RegistrationChallengeStore(private val redis: JedisPooled) {
    companion object {
        /** Not private: AppAttestVerification derives the attestation receipt's max age from it. */
        val TTL: Duration = Duration.ofMinutes(15)
        private const val KEY_PREFIX = "challenge:register:"
    }

    /** Returns the raw challenge bytes to send to the client. */
    fun issue(identityPublicKeyBase64: String): ByteArray {
        val challenge = randomBytes(32)
        redis.setex(KEY_PREFIX + base64.encodeToString(challenge), TTL.seconds, identityPublicKeyBase64)
        return challenge
    }

    /**
     * Single-use: consumes the challenge, returning the identityPublicKey it
     * was issued for, or null if the challenge is unknown, expired, or
     * already consumed.
     */
    fun consume(challenge: ByteArray): String? =
        redis.getDel(KEY_PREFIX + base64.encodeToString(challenge))
}

/**
 * Session nonces. 60s TTL — much shorter than the registration challenge,
 * because nothing is cached against it (attestation-assertion-workflow.md).
 */
class SessionNonceStore(private val redis: JedisPooled) {
    companion object {
        private val TTL: Duration = Duration.ofSeconds(60)
        private const val KEY_PREFIX = "challenge:session:"
    }

    fun issue(): ByteArray {
        val nonce = randomBytes(32)
        redis.setex(KEY_PREFIX + base64.encodeToString(nonce), TTL.seconds, "1")
        return nonce
    }

    /** Single-use: true if the nonce was present (and is now consumed). */
    fun consume(nonce: ByteArray): Boolean =
        redis.getDel(KEY_PREFIX + base64.encodeToString(nonce)) != null
}

/**
 * Opaque, short-lived session tokens. Not a JWT — no claims worth signing
 * locally when a Redis round-trip already happens on every session-scoped
 * call, and an opaque token can be revoked by deleting the key, which a
 * self-contained JWT cannot.
 */
class SessionTokenStore(private val redis: JedisPooled) {
    companion object {
        private val TTL: Duration = Duration.ofMinutes(15)
        private const val KEY_PREFIX = "session:token:"
    }

    fun issue(accountUuid: UUID): String {
        val token = base64.encodeToString(randomBytes(32))
        redis.setex(KEY_PREFIX + token, TTL.seconds, accountUuid.toString())
        return token
    }

    fun accountFor(token: String): UUID? =
        redis.get(KEY_PREFIX + token)?.let(UUID::fromString)
}
