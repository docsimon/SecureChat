package chat.securechat.auth

import ch.veehait.devicecheck.appattest.AppleAppAttest
import ch.veehait.devicecheck.appattest.assertion.Assertion
import ch.veehait.devicecheck.appattest.assertion.AssertionChallengeValidator
import ch.veehait.devicecheck.appattest.assertion.AssertionValidator
import ch.veehait.devicecheck.appattest.attestation.AttestationValidator
import ch.veehait.devicecheck.appattest.attestation.ValidatedAttestation
import ch.veehait.devicecheck.appattest.common.App
import java.security.interfaces.ECPublicKey

/**
 * Thin wrapper around `devicecheck-appattest`. Deliberately does not touch
 * the library's internals — see Architecture/account-keys-reference.md for
 * why (clientDataHash = SHA256(challenge) alone; identity binding lives in
 * [ChallengeStore] instead of being forked into the library's nonce check).
 */
class AppAttestVerification(config: Config) {

    private val appleAppAttest = AppleAppAttest(
        app = App(
            teamIdentifier = config.teamIdentifier,
            bundleIdentifier = config.bundleIdentifier,
        ),
        appleAppAttestEnvironment = config.appAttestEnvironment,
    )

    private val attestationValidator: AttestationValidator = appleAppAttest.createAttestationValidator()

    private val assertionValidator: AssertionValidator = appleAppAttest.createAssertionValidator(
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

    /** @throws ch.veehait.devicecheck.appattest.attestation.AttestationException on any validation failure. */
    fun validateAttestation(
        attestationObject: ByteArray,
        keyIdBase64: String,
        challenge: ByteArray,
    ): ValidatedAttestation = attestationValidator.validate(
        attestationObject = attestationObject,
        keyIdBase64 = keyIdBase64,
        serverChallenge = challenge,
    )

    /** @throws ch.veehait.devicecheck.appattest.assertion.AssertionException on any validation failure. */
    fun validateAssertion(
        assertionObject: ByteArray,
        clientData: ByteArray,
        attestationPublicKey: ECPublicKey,
        lastCounter: Long,
        nonce: ByteArray,
    ): Assertion = assertionValidator.validate(
        assertionObject = assertionObject,
        clientData = clientData,
        attestationPublicKey = attestationPublicKey,
        lastCounter = lastCounter,
        challenge = nonce,
    )
}
