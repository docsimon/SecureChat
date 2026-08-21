//
//  NetworkCommon.swift
//  SecureChat
//
//  Created by Simone Barbara on 14/08/2026.
//

import Foundation

enum BaseAddress {
  
    case baseAddressAuth
    case baseAddressRelay
#if DEBUG
    case baseAddressEcho
#endif
    
    func getBaseAddress() -> String {
        switch self {
        case .baseAddressAuth:
            return "http://localhost:8080/"
        case .baseAddressRelay:
            return "http://localhost:8080/relay"
#if DEBUG
        case .baseAddressEcho:
            return "http://localhost:8080/echo"
#endif
        }
    }
}


enum Endpoint {
    case register
    case verify
    case resend
    case updatePhone(userID: UUID)
    
    
    func getEndpoint() -> String {
        switch self {
        case .register:
            return "register"
        case .verify:
            return "register/verify"
        case .resend:
            return "register/resend"
        case .updatePhone(let userID):
            return "users/\(userID)/phone"
        }
        
    }
}

enum HTTPMethodType {
    case get
    case post
    case put
    case patch
    
    func getMethod() -> String {
        switch self {
        case .get:
            return "GET"
        case .post:
            return "POST"
        case .put:
            return "PUT"
        case .patch:
            return "PATCH"
        }
    }
}

enum NetworkUtilities {
    
    static func createURL(from endpoint: String) throws -> URL {
        guard let url = URL(string: endpoint) else {
            throw NetworkError.badURL
        }
        
        return url
    }
    
    static func createRequest(with url: URL, httpMethod: HTTPMethodType, httpBody: Data?) -> URLRequest {
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = httpMethod.getMethod()
        urlRequest.httpBody = httpBody
        
        return urlRequest
        
    }
   
}
