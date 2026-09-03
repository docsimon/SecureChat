//
//  DefaultKeyStore.swift
//  AppAttestKit
//
//  Created by Simone Barbara on 02/09/2026.
//

import Foundation

struct DefaultKeyStore: AttestationKeyStore {
    func loadKeyId() throws -> String? {
        nil
    }
    
    func store(keyId: String) throws {
        
    }
    
    func loadIsAttested() throws -> Bool {
        false
    }
    
    func store(isAttested: Bool) throws {
        
    }
    
    func loadAttestation() throws -> (object: Data, challenge: Data)? {
        nil
    }
    
    func store(attestation: Data, challenge: Data) throws {
        
    }
    
    func clearAttestation() throws {
        
    }
    
    func loadRegenerationCount() throws -> Int {
        1
    }
    
    func store(regenerationCount: Int) throws {
        
    }
    
    func clear() throws {
        
    }
}
