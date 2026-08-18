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

enum RegistrationError: Error {
    case ownerAlreadyRegistered
    case ownerDoesNOTExist
    case phoneNumberRegistration
}

protocol AuthService {
    func register(data: RegistrationDTO, method: HTTPMethodType) async throws
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
    
    // this function is used to initially register the owner id on the auth server along with its phone number
    // and PN token (method POST)
    // then is used to send the OTP code to validate the phone number (method UPDATE)
    func register(data: RegistrationDTO, method: HTTPMethodType) async throws {
        let body = try jsonAdapter.serialize(data: data)
        let baseAddress = BaseAddress.baseAddressAuth.getBaseAddress()
        let endpoint = Endpoint.register.getEndpoint()
        let url = try NetworkUtilities.createURL(from: baseAddress + endpoint)
        let request = NetworkUtilities.createRequest(with: url, httpMethod: method, httpBody: body)
        
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
