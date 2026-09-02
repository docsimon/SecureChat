//
//  AttestService
//
//
//  Created by Simone Barbara on 30/08/2026.
//

import Foundation
import DeviceCheck

public protocol AttestServicing: Sendable {
    var isSupported: Bool { get }
    func generateKey() async throws -> String
    func attestKey(_ keyId: String, clientDataHash: Data) async throws -> Data
    func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data
}



public struct AttestService: AttestServicing {
    
    public init() {}
    
    //MARK: AttestServicing Protocol
    
    public var isSupported: Bool {
        DCAppAttestService.shared.isSupported
    }
    
    public func generateKey() async throws -> String {
        try await DCAppAttestService.shared.generateKey()
    }
    
    public func attestKey(_ keyId: String, clientDataHash: Data) async throws -> Data {
        try await DCAppAttestService.shared.attestKey(keyId, clientDataHash: clientDataHash)
    }
    
    public func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data {
        try await DCAppAttestService.shared.generateAssertion(keyId, clientDataHash: clientDataHash)
    }
    
}
