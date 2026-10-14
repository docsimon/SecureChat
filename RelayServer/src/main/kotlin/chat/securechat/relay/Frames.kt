package chat.securechat.relay

import java.nio.ByteBuffer
import java.util.UUID

/**
 * The relay's view of a frame (session-workflow.md, "Wire format"): it reads
 * the first 18 bytes and never the body, which is encrypted end to end.
 *
 *   [0]      version = 1
 *   [1]      kind: 1 deliver, 2 peer unavailable
 *   [2..17]  peer routing id
 *   [18..]   body
 */
object Frames {
    const val SIZE = 8_320
    const val VERSION: Byte = 1
    const val KIND_DELIVER: Byte = 1
    const val KIND_PEER_UNAVAILABLE: Byte = 2
    private const val PEER_OFFSET = 2
    private const val ID_SIZE = 16

    /** The destination of a client's frame, or null if the frame is not one the relay forwards. */
    fun destination(frame: ByteArray): UUID? {
        if (frame.size != SIZE || frame[0] != VERSION || frame[1] != KIND_DELIVER) return null
        return uuid(frame, PEER_OFFSET)
    }

    /** The same frame, now naming who sent it. The relay vouches for that id. */
    fun fromSender(frame: ByteArray, sender: UUID): ByteArray =
        frame.copyOf().also { write(sender, it, PEER_OFFSET) }

    fun peerUnavailable(peer: UUID): ByteArray =
        ByteArray(SIZE).also {
            it[0] = VERSION
            it[1] = KIND_PEER_UNAVAILABLE
            write(peer, it, PEER_OFFSET)
        }

    /** Big endian, RFC 4122 byte order: the same 16 bytes as Swift's `UUID.uuid`. */
    fun bytes(id: UUID): ByteArray =
        ByteBuffer.allocate(ID_SIZE).putLong(id.mostSignificantBits).putLong(id.leastSignificantBits).array()

    private fun uuid(bytes: ByteArray, offset: Int): UUID {
        val buffer = ByteBuffer.wrap(bytes, offset, ID_SIZE)
        return UUID(buffer.long, buffer.long)
    }

    private fun write(id: UUID, into: ByteArray, offset: Int) {
        bytes(id).copyInto(into, offset)
    }
}
