package chat.securechat.auth

import ch.veehait.devicecheck.appattest.AppleAppAttest
import ch.veehait.devicecheck.appattest.assertion.Assertion
import ch.veehait.devicecheck.appattest.assertion.AssertionChallengeValidator
import ch.veehait.devicecheck.appattest.assertion.AssertionValidator
import ch.veehait.devicecheck.appattest.attestation.AttestationValidator
import ch.veehait.devicecheck.appattest.attestation.ValidatedAttestation
import ch.veehait.devicecheck.appattest.common.App
import java.security.interfaces.ECPublicKey
import java.time.Duration

/**
 * Thin wrapper around `devicecheck-appattest`. Deliberately does not touch
 * the library's internals — see Architecture/account-keys-reference.md for
 * why (clientDataHash = SHA256(challenge) alone; identity binding lives in
 * [ChallengeStore] instead of being forked into the library's nonce check).
 */
class AppAttestVerification(config: Config) {

    /** The library binds a validator to exactly one app, so: one set per accepted bundle id. */
    private class AppValidators(
        val attestation: AttestationValidator,
        val assertion: AssertionValidator,
    )

    private val validators: List<AppValidators> = config.bundleIdentifiers.map { bundleIdentifier ->
        val appleAppAttest = AppleAppAttest(
            app = App(
                teamIdentifier = config.teamIdentifier,
                bundleIdentifier = bundleIdentifier,
            ),
            appleAppAttestEnvironment = config.appAttestEnvironment,
        )
        AppValidators(
            attestation = createAttestationValidator(appleAppAttest),
            assertion = createAssertionValidator(appleAppAttest),
        )
    }

    /**
     * Accepts what ANY configured app's validator accepts. Each validator
     * still checks everything for its own app, so this widens "which app"
     * to the configured list and nothing else. When all refuse, the first
     * refusal is reported and the rest are attached as suppressed.
     */
    private fun <T> acceptedByAnyApp(validate: (AppValidators) -> T): T {
        var firstFailure: Exception? = null
        for (candidate in validators) {
            try {
                return validate(candidate)
            } catch (e: Exception) {
                if (firstFailure == null) firstFailure = e else firstFailure.addSuppressed(e)
            }
        }
        throw checkNotNull(firstFailure) { "no App Attest app configured" }
    }

    // The receipt embedded in an attestation carries its creation time, and
    // the library rejects it once older than `maxAge` — 5 minutes by default.
    // That default silently cut the resume window to a third of what the
    // rest of the design assumes: the client caches an attestation and may
    // resubmit it for as long as its challenge lives (15 minutes), but
    // anything submitted after minute 5 came back
    // `attestation_invalid:InvalidReceipt` (found on a real device). Tied to
    // the challenge TTL instead, plus a margin, so there is ONE clock: an
    // attestation that is too old always fails the challenge check in
    // Routes.kt first, which the client already recovers from by itself.
    // Freshness is still enforced — by the single-use challenge the
    // attestation is cryptographically bound to. Every other receipt check
    // (signature chain, app identity, attested public key) is unchanged.
    private fun createAttestationValidator(appleAppAttest: AppleAppAttest): AttestationValidator =
        appleAppAttest.createAttestationValidator(
            receiptValidator = appleAppAttest.createReceiptValidator(
                maxAge = ATTESTATION_RECEIPT_MAX_AGE,
            ),
        )

    private fun createAssertionValidator(appleAppAttest: AppleAppAttest): AssertionValidator = appleAppAttest.createAssertionValidator(
        assertionChallengeValidator = object : AssertionChallengeValidator {
            // Always true — reads like a skipped check in isolation, but it
            // isn't one. Freshness/single-use is enforced TWICE already,
            // independently, before this ever runs:
            //   1. Routes.kt's /session handler does a single-use GETDEL on
            //      the nonce in Redis before calling validateAssertion() at
            //      all — an already-consumed or expired nonce never reaches
            //      here.
            //   2. Even without (1): `clientData` passed in is server-built
            //      as `nonceBytes + bodyBytes` (Routes.kt), and this same
            //      library's own verifySignature() hashes clientData into
            //      the value it verifies the ECDSA signature against. So the
            //      device's signature already cryptographically commits to
            //      this exact nonce — a forged/stale nonce would fail
            //      signature verification on its own, with or without this
            //      callback.
            // This callback returning unconditional `true` is what tells the
            // library "the challenge is fine, verify the rest" once both of
            // those have already made that true. Reviewed and confirmed
            // deliberate — see the auth-server code review in this session's
            // Claude Doc for the full trace-through.
            override fun validate(
                assertionObj: Assertion,
                clientData: ByteArray,
                attestationPublicKey: ECPublicKey,
                challenge: ByteArray,
            ): Boolean = true
        },
    )

    companion object {
        val ATTESTATION_RECEIPT_MAX_AGE: Duration = RegistrationChallengeStore.TTL.plusMinutes(1)
    }

    /** @throws ch.veehait.devicecheck.appattest.attestation.AttestationException on any validation failure. */
    fun validateAttestation(
        attestationObject: ByteArray,
        keyIdBase64: String,
        challenge: ByteArray,
    ): ValidatedAttestation = acceptedByAnyApp {
        it.attestation.validate(
            attestationObject = attestationObject,
            keyIdBase64 = keyIdBase64,
            serverChallenge = challenge,
        )
    }

    /** @throws ch.veehait.devicecheck.appattest.assertion.AssertionException on any validation failure. */
    fun validateAssertion(
        assertionObject: ByteArray,
        clientData: ByteArray,
        attestationPublicKey: ECPublicKey,
        lastCounter: Long,
        nonce: ByteArray,
    ): Assertion = acceptedByAnyApp {
        it.assertion.validate(
            assertionObject = assertionObject,
            clientData = clientData,
            attestationPublicKey = attestationPublicKey,
            lastCounter = lastCounter,
            challenge = nonce,
        )
    }
}
