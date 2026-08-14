//
//  AuthService.swift
//  SecureChat
//
//  Created by doc on 14/08/2026.
//
import Foundation

protocol AuthService {
    // the user sends its own phone number, username and push notification token when registering to the auth server
    func register(phone: String, username: String, token: String) async throws
    func invite() async throws
    func getInvites() async throws -> [Data]
    func acceptInvite() async throws
    func declineInvite() async throws
}


struct AuthServiceImpl: AuthService {
   
    let networkAdapter: NetworkAdapter
    
    init(networkAdapter: NetworkAdapter) {
        self.networkAdapter = networkAdapter
    }
    

    
    //MARK: AuthService Protocol
    func register(phone: String, username: String, token: String) async throws {
    
    }
    
    func invite() async throws {
        
    }
    
    func getInvites() async throws -> [Data] {
        []
    }
    
    
    func acceptInvite() async throws {
        
    }
    
    func declineInvite() async throws {
        
    }
    
}
