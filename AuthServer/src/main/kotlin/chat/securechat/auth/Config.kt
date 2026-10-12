package chat.securechat.auth

import ch.veehait.devicecheck.appattest.common.AppleAppAttestEnvironment

/**
 * Everything environment-specific comes from env vars, always overridden by
 * docker-compose.yml/.env in practice. `postgresUrl`/`postgresUser`/
 * `postgresPassword`/`redisUrl`/`port` fall back to plain localhost
 * defaults ONLY to keep `./gradlew run` usable against a locally-installed
 * Postgres/Redis without Docker — a forgotten `DATABASE_URL` in a real
 * deployment fails loudly on the first connection attempt, not silently.
 * `APPATTEST_TEAM_ID`/`APPATTEST_BUNDLE_ID`/`APPATTEST_ENVIRONMENT`
 * deliberately have NO default and error at startup if missing — silently
 * defaulting the App Attest environment would be a real security bug
 * (accepting dev-signed attestations against a production deployment), not
 * just an inconvenience. Same container image runs everywhere either way
 * (AuthServer/README.md).
 *
 * `APPATTEST_BUNDLE_ID` may list several apps, comma-separated. That exists
 * for DEVELOPMENT, where the real app and its test harness are two bundle
 * ids sharing one server. Every id listed can register accounts, so a
 * production deployment lists the shipped app and nothing else.
 */
data class Config(
    val port: Int,
    val teamIdentifier: String,
    val bundleIdentifiers: List<String>,
    val appAttestEnvironment: AppleAppAttestEnvironment,
    val postgresUrl: String,
    val postgresUser: String,
    val postgresPassword: String,
    val redisUrl: String,
) {
    companion object {
        fun fromEnv(): Config {
            fun env(name: String, default: String? = null): String =
                System.getenv(name) ?: default
                    ?: error("Missing required environment variable: $name")

            return Config(
                port = env("PORT", "8080").toInt(),
                teamIdentifier = env("APPATTEST_TEAM_ID"),
                bundleIdentifiers = parseBundleIdentifiers(env("APPATTEST_BUNDLE_ID")),
                appAttestEnvironment = when (env("APPATTEST_ENVIRONMENT")) {
                    "development" -> AppleAppAttestEnvironment.DEVELOPMENT
                    "production" -> AppleAppAttestEnvironment.PRODUCTION
                    else -> error(
                        "APPATTEST_ENVIRONMENT must be 'development' or 'production'",
                    )
                },
                postgresUrl = env("DATABASE_URL", "jdbc:postgresql://localhost:5432/authserver"),
                postgresUser = env("DATABASE_USER", "authserver"),
                postgresPassword = env("DATABASE_PASSWORD", "authserver"),
                redisUrl = env("REDIS_URL", "redis://localhost:6379"),
            )
        }

        fun parseBundleIdentifiers(raw: String): List<String> =
            raw.split(",").map { it.trim() }.filter { it.isNotEmpty() }.distinct()
                .ifEmpty { error("APPATTEST_BUNDLE_ID must name at least one bundle id") }
    }
}
