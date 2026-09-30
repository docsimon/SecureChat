package chat.securechat.auth

import com.zaxxer.hikari.HikariConfig
import com.zaxxer.hikari.HikariDataSource
import java.security.KeyFactory
import java.security.interfaces.ECPublicKey
import java.security.spec.X509EncodedKeySpec
import java.sql.Connection
import java.sql.ResultSet
import java.util.UUID
import javax.sql.DataSource

data class Account(
    val accountUuid: UUID,
    val keyId: ByteArray,
    val attestPublicKey: ECPublicKey,
    val counter: Long,
)

/**
 * The durable half of the auth server's state (Redis holds the ephemeral
 * half). One table — an ORM would be pure overhead for this shape.
 */
class AccountRepository(private val dataSource: DataSource) {

    companion object {
        fun createDataSource(config: Config): DataSource {
            val hikariConfig = HikariConfig().apply {
                jdbcUrl = config.postgresUrl
                username = config.postgresUser
                password = config.postgresPassword
                maximumPoolSize = 10
            }
            return HikariDataSource(hikariConfig)
        }
    }

    fun migrate() {
        dataSource.connection.use { conn ->
            conn.createStatement().use { stmt ->
                stmt.execute(
                    """
                    CREATE TABLE IF NOT EXISTS accounts (
                        account_uuid  UUID PRIMARY KEY,
                        key_id        BYTEA NOT NULL UNIQUE,
                        attest_pubkey BYTEA NOT NULL,
                        counter       BIGINT NOT NULL DEFAULT 0,
                        created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
                    )
                    """.trimIndent(),
                )
            }
        }
    }

    /**
     * Idempotent on [keyId]: if this key already registered, returns the
     * existing account untouched rather than erroring — the client may
     * retry after a lost response (architecture-decisions.md §6).
     */
    fun registerOrReturnExisting(keyId: ByteArray, attestPublicKey: ECPublicKey): Account {
        dataSource.connection.use { conn ->
            findByKeyId(conn, keyId)?.let { return it }

            val accountUuid = UUID.randomUUID()
            conn.prepareStatement(
                """
                INSERT INTO accounts (account_uuid, key_id, attest_pubkey, counter)
                VALUES (?, ?, ?, 0)
                ON CONFLICT (key_id) DO NOTHING
                """.trimIndent(),
            ).use { stmt ->
                stmt.setObject(1, accountUuid)
                stmt.setBytes(2, keyId)
                stmt.setBytes(3, attestPublicKey.encoded)
                stmt.executeUpdate()
            }

            // Either our insert won (this is the new account) or a concurrent
            // request beat us to it — either way, read back the row that's
            // actually there now.
            return findByKeyId(conn, keyId)
                ?: error("Account for key_id disappeared immediately after insert")
        }
    }

    fun findByKeyId(keyId: ByteArray): Account? =
        dataSource.connection.use { conn -> findByKeyId(conn, keyId) }

    private fun findByKeyId(conn: Connection, keyId: ByteArray): Account? {
        conn.prepareStatement(
            "SELECT account_uuid, key_id, attest_pubkey, counter FROM accounts WHERE key_id = ?",
        ).use { stmt ->
            stmt.setBytes(1, keyId)
            stmt.executeQuery().use { rs -> return rs.toAccountOrNull() }
        }
    }

    /**
     * `/session` looks accounts up by this, not [findByKeyId] — `keyId` is
     * never available to the app at sign()-time (`AssertionSigning.sign(_:)`
     * deliberately never exposes it, by module design), while `account_uuid`
     * is exactly what the app is meant to hold onto long-term after
     * registration (architecture-decisions.md: "Client stores the UUID").
     */
    fun findByAccountUuid(accountUuid: UUID): Account? =
        dataSource.connection.use { conn ->
            conn.prepareStatement(
                "SELECT account_uuid, key_id, attest_pubkey, counter FROM accounts WHERE account_uuid = ?",
            ).use { stmt ->
                stmt.setObject(1, accountUuid)
                stmt.executeQuery().use { rs -> return rs.toAccountOrNull() }
            }
        }

    private fun ResultSet.toAccountOrNull(): Account? {
        if (!next()) return null
        return Account(
            accountUuid = getObject("account_uuid", UUID::class.java),
            keyId = getBytes("key_id"),
            attestPublicKey = decodeEcPublicKey(getBytes("attest_pubkey")),
            counter = getLong("counter"),
        )
    }

    /**
     * The counter must be strictly greater than [expectedPreviousCounter] —
     * enforced here, not just at the validation step, to close the race
     * between two concurrent requests validating against the same stale
     * counter and both trying to persist.
     */
    fun advanceCounter(keyId: ByteArray, expectedPreviousCounter: Long, newCounter: Long): Boolean {
        dataSource.connection.use { conn ->
            conn.prepareStatement(
                "UPDATE accounts SET counter = ? WHERE key_id = ? AND counter = ?",
            ).use { stmt ->
                stmt.setLong(1, newCounter)
                stmt.setBytes(2, keyId)
                stmt.setLong(3, expectedPreviousCounter)
                return stmt.executeUpdate() == 1
            }
        }
    }

    private fun decodeEcPublicKey(encoded: ByteArray): ECPublicKey =
        KeyFactory.getInstance("EC").generatePublic(X509EncodedKeySpec(encoded)) as ECPublicKey
}
