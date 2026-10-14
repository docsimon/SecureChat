package chat.securechat.relay

/**
 * Environment-specific settings (session-workflow.md, "Relay").
 *
 * `RELAY_DEV_CLAIMED_ACCOUNTS` lets a client connect by simply naming an
 * account (`X-Dev-Account`), with no session token. It exists so Simulators,
 * Debug builds and the session harness can reach the relay without App
 * Attest. Anyone who can reach a relay with it on can impersonate any
 * account, so it is off unless set to exactly "true", and never set in
 * production.
 */
data class Config(
    val port: Int,
    val redisUrl: String,
    val devClaimedAccounts: Boolean,
) {
    companion object {
        fun fromEnv(): Config = Config(
            port = (System.getenv("PORT") ?: "8081").toInt(),
            redisUrl = System.getenv("REDIS_URL") ?: "redis://localhost:6379",
            devClaimedAccounts = System.getenv("RELAY_DEV_CLAIMED_ACCOUNTS") == "true",
        )
    }
}
