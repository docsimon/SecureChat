//
//  EnvironmentLoggingTransport.swift
//  SecureChat
//
//  Debug builds only. When the "SecureChat Real Registration" scheme runs
//  the real flow, this logs which App Attest environment Apple's answer came
//  from, read from the attestation itself (the same check as the harness's
//  badge), so a run can confirm it never touched production.
//

#if DEBUG
import Foundation
import AppAttestKit
import RegistrationKit

struct EnvironmentLoggingTransport: AttestationTransport {
    let base: AttestationTransport

    func fetchChallenge() async throws -> Data {
        try await base.fetchChallenge()
    }

    func submitAttestation(_ request: AttestationSubmission) async throws -> String {
        switch AttestationEnvironmentHint.environment(of: request.attestation) {
        case .development:
            SCLogger.logger.info(message: "App Attest environment: development", category: .Registration)
        case .production:
            SCLogger.logger.error(message: "⚠️ App Attest environment: PRODUCTION in a Debug build. Stop and check the entitlement and how this build was installed.", category: .Registration)
        case .unrecognised:
            SCLogger.logger.error(message: "⚠️ App Attest environment not recognised: \(AttestationEnvironmentHint.describe(request.attestation))", category: .Registration)
        }
        return try await base.submitAttestation(request)
    }
}
#endif
