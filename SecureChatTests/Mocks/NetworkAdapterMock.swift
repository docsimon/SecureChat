//
//  NetworkAdapterMock.swift
//  SecureChat
//
//  Created by doc on 14/08/2026.
//

import Foundation
@testable import SecureChat

class NetworkAdapterMock: NetworkAdapter {
    
    var mockRequest: URLRequest?

    func fetch(data: Data, from url: URL) async throws -> Data {
        return "test".data(using: .utf8)!
    }
    
    func send(request: URLRequest) async throws {
        mockRequest = request
    }
    
}
