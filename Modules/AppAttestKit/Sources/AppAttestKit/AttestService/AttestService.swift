//
//  AttestService
//
//
//  Created by Simone Barbara on 30/08/2026.
//

import Foundation
import DeviceCheck

/// Seam over `DCAppAttestService`, which is a concrete class that cannot be
/// subclassed or stubbed and only returns errors on real hardware.
protocol AttestServicing: Sendable {
    var isSupported: Bool { get }
    func generateKey() async throws -> String
    func attestKey(_ keyId: String, clientDataHash: Data) async throws -> Data
    func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data
}


/// Live implementation — thin pass-through to `DCAppAttestService.shared`.
/// Named `Live...` (not just `AttestService`) to read clearly next to the
/// mock used in tests, and to avoid being confused with the `AttestServicing`
/// protocol it conforms to.
struct LiveAttestService: AttestServicing {

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
