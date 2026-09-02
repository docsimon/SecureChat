//
//  AttestationKeyStore.swift
//  AppAttestKit
//
//  Created by Simone Barbara on 30/08/2026.
//

import Foundation

public protocol AttestationKeyStore: Sendable {
    func loadKeyId() throws -> String?
    func store(keyId: String) throws
    func loadAttestation() throws -> (object: Data, challenge: Data)?
    func store(attestation: Data, challenge: Data) throws
    func clearAttestation() throws
    func clear() throws
}
