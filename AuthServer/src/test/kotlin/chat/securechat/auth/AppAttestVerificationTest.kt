package chat.securechat.auth

import ch.veehait.devicecheck.appattest.receipt.ReceiptValidator
import kotlin.test.Test
import kotlin.test.assertTrue

class AppAttestVerificationTest {

    /**
     * A cached attestation may be resubmitted for as long as its challenge
     * lives. If the receipt age limit ever drops below the challenge TTL
     * again (the library default is 5 minutes), resubmissions in the gap are
     * rejected as `attestation_invalid:InvalidReceipt` instead of accepted.
     */
    @Test
    fun `attestation receipt max age covers the whole challenge lifetime`() {
        assertTrue(AppAttestVerification.ATTESTATION_RECEIPT_MAX_AGE > RegistrationChallengeStore.TTL)
        assertTrue(AppAttestVerification.ATTESTATION_RECEIPT_MAX_AGE > ReceiptValidator.APPLE_RECOMMENDED_MAX_AGE)
    }
}
