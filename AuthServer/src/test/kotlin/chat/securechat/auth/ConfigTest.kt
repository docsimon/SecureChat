package chat.securechat.auth

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

class ConfigTest {

    @Test
    fun `a single bundle id still works`() {
        assertEquals(listOf("com.example.App"), Config.parseBundleIdentifiers("com.example.App"))
    }

    @Test
    fun `several bundle ids are split, trimmed and de-duplicated`() {
        assertEquals(
            listOf("com.example.App", "com.example.Harness"),
            Config.parseBundleIdentifiers(" com.example.App , com.example.Harness,com.example.App,"),
        )
    }

    @Test
    fun `an empty list is refused rather than accepting nothing silently`() {
        assertFailsWith<IllegalStateException> { Config.parseBundleIdentifiers(" , ") }
    }
}
