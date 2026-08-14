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
            return "http://localhost:8080"
        case .baseAddressRelay:
            return "http://localhost:8081"
#if DEBUG
        case .baseAddressEcho:
            return "http://localhost:8082"
#endif
        }
    }
}


enum Endpoint {
    case register
    case invite
    case invites
    case inviteAccept
    case inviteDecline
    case chats
    
    func getEndpoint() -> String {
        switch self {
        case .register:
            return "register"
        case .invite:
            return "invite"
        case .invites:
            return "invites"
        case .inviteAccept:
            return "invite/accept"
        case .inviteDecline:
            return "invite/decline"
        case .chats:
            return "chats"
        }
        
    }
}

enum RequestType {
    case get
    case post
}

enum NetworkUtilities {
    
    func createURL(from endpoint: String) throws -> URL {
        guard let url = URL(string: endpoint) else {
            throw NetworkError.badURL
        }
        
        return url
    }
    
//    func createRequest(with url: URL, type: RequestType) -> URLRequest {
//        let urlRequest = URLRequest(url: url)
//        urlRequest.httpBody
//    }
}
