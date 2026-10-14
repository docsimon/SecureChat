package chat.securechat.relay

import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

/**
 * Who is connected, in memory only. An entry exists exactly as long as its
 * connection: nothing about who talked to whom outlives a disconnect
 * (architecture-decisions.md §1).
 *
 * One connection per account. An account is one install on one phone, so a
 * second connection means the app reconnected: it replaces the first.
 */
class Router<C : Any> {
    private val connections = ConcurrentHashMap<UUID, C>()

    /** Returns the connection this one replaced, for the caller to close. */
    fun register(account: UUID, connection: C): C? = connections.put(account, connection)

    /** Only removes the entry if it is still this connection, not a newer one. */
    fun unregister(account: UUID, connection: C) {
        connections.remove(account, connection)
    }

    fun connection(account: UUID): C? = connections[account]

    val size: Int get() = connections.size
}
