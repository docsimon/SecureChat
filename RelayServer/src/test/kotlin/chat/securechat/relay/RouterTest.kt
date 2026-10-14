package chat.securechat.relay

import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class RouterTest {
    @Test
    fun `a reconnect replaces the old connection, and the old one leaving does not remove the new one`() {
        val router = Router<String>()
        val id = UUID.randomUUID()
        assertNull(router.register(id, "first"))
        assertEquals("first", router.register(id, "second"))

        router.unregister(id, "first")

        assertEquals("second", router.connection(id))
        router.unregister(id, "second")
        assertNull(router.connection(id))
    }

    @Test
    fun `routing ids use the same byte order as Swift's UUID`() {
        val id = UUID.fromString("00112233-4455-6677-8899-aabbccddeeff")
        assertEquals("00112233445566778899aabbccddeeff",
                     Frames.bytes(id).joinToString("") { "%02x".format(it) })
    }
}
