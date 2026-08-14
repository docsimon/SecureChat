//
//  AuthService.swift
//  SecureChat
//
//  Created by doc on 14/08/2026.
//
import Foundation

/*
 This struct manages all the interactions with the auth server
 - registration
 - invites
 */

protocol AuthService {
    // the user sends its own phone number, username and push notification token when registering to the auth server
    func register(data: RegistrationDTO) async throws
    func invite() async throws
    func getInvites() async throws -> [Data]
    func acceptInvite() async throws
    func declineInvite() async throws
}


struct AuthServiceImpl: AuthService {
   
    let networkAdapter: NetworkAdapter
    let jsonAdapter: JSONAdapter
    
    init(networkAdapter: NetworkAdapter, jsonAdapter: JSONAdapter) {
        self.networkAdapter = networkAdapter
        self.jsonAdapter = jsonAdapter
    }
    
    //MARK: AuthService Protocol
    func register(data: RegistrationDTO) async throws {
        let body = try jsonAdapter.serialize(data: data)
        let baseAddress = BaseAddress.baseAddressAuth.getBaseAddress()
        let endpoint = Endpoint.register.getEndpoint()
        let url = try NetworkUtilities.createURL(from: baseAddress + endpoint)
        let request = NetworkUtilities.createRequest(with: url, httpMethod: .post, httpBody: body)
        
        try await networkAdapter.send(request: request)
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
