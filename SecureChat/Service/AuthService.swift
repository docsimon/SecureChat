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
    func registerWithPhone(phone: String, displayName: String, userID: UUID, pushToken: String) async throws
    func registerWithEmail(email: String, displayName: String, userID: UUID, pushToken: String) async throws
    func verify(userID: UUID, code: String) async throws
    func updatePhone(userID: UUID, phone: String) async throws
}


struct AuthServiceImpl: AuthService {

    let networkAdapter: NetworkAdapter
    let jsonAdapter: JSONAdapter
    let baseAddress: BaseAddress
    
    init(networkAdapter: NetworkAdapter, jsonAdapter: JSONAdapter, baseAddress: BaseAddress) {
        self.networkAdapter = networkAdapter
        self.jsonAdapter = jsonAdapter
        self.baseAddress = baseAddress
    }
    
    //MARK: AuthService Protocol
    
    // POST
    func registerWithPhone(phone: String, displayName: String, userID: UUID, pushToken: String) async throws {
        
        let dto = RegistrationWithPhoneDTO(userID: userID, phone: phone, pushToken: pushToken, displayName: displayName)
        let request = try buildRequest(with: dto, endpoint: .register, httpMethod: .post)
        do {
            _ = try await networkAdapter.send(request: request)
        } catch NetworkError.unsuccessfulResponse(let code, let payload) {
            throw mapError(status: code, payload: payload)
        }
    }
    
    // POST
    func registerWithEmail(email: String, displayName: String, userID: UUID, pushToken: String) async throws {
        
        let dto = RegistrationWithEmailDTO(userID: userID, email: email, pushToken: pushToken, displayName: displayName)
        let request = try buildRequest(with: dto, endpoint: .register, httpMethod: .post)
        do {
            _ = try await networkAdapter.send(request: request)
        } catch NetworkError.unsuccessfulResponse(let code, let payload) {
            throw mapError(status: code, payload: payload)
        }
    }
    
    // POST
    func verify(userID: UUID, code: String) async throws {
        let dto = RegistrationOTPVerificationDTO(userID: userID, code: code)
        let request = try buildRequest(with: dto, endpoint: .verify, httpMethod: .post)
        do {
            _ = try await networkAdapter.send(request: request)
        } catch NetworkError.unsuccessfulResponse(let code, let payload) {
            throw mapError(status: code, payload: payload)
        }
    }
    
    func updatePhone(userID: UUID, phone: String) async throws {
        let dto = RegistrationUpdatePhone(phone: phone)
        let request = try buildRequest(with: dto, endpoint: .updatePhone(userID: userID), httpMethod: .put)
        do {
            _ = try await networkAdapter.send(request: request)
        } catch NetworkError.unsuccessfulResponse(let code, let payload) {
            throw mapError(status: code, payload: payload)
        }
    }
    
    //MARK: Private methods
    
    private func buildRequest(with dto: Codable, endpoint: Endpoint, httpMethod: HTTPMethodType) throws -> URLRequest {
        let body = try jsonAdapter.serialize(data: dto)
        let baseAddress = baseAddress.getBaseAddress()
        let endpoint = endpoint.getEndpoint()
        let url = try NetworkUtilities.createURL(from: baseAddress + endpoint)
        
        return NetworkUtilities.createRequest(with: url, httpMethod: .post, httpBody: body)
    }

    private func mapError(status: Int, payload: Data) -> RegistrationError {
        guard let payload: PayloadErrorResponse = try? jsonAdapter.deserialize(data: payload) else {
            return .unexpected(status: status, code: "")
        }
        switch payload.error {
        case .invalidCode:    return .invalidOTPCode(attemptsRemaining: payload.attemptsRemaining ?? 0)
        case .resendTooSoon:  return .resendTooSoon(retryAfterMs: payload.retryAfterMs ?? 30_000)
        case .codeExpired:    return .codeExpired
        case .phoneRequired: return .phoneRequired
        case .phoneTaken: return .phoneTaken
        case .tooManyAttempts: return .tooManyAttempts
        case .unknownUser: return .unknownUser
        case .unknown(let raw): return .unexpected(status: status, code: raw)
        }
    }
}
