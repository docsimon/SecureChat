//
//  NetworkAdapter.swift
//  SecureChat
//
//  Created by Simone Barbara on 14/08/2026.
//

import Foundation

enum NetworkError: Error {
    case badURL
    case badHttpResponse
    case unsuccessfulResponse(code: Int)
}


protocol NetworkAdapter {
    func fetch(data: Data,  from url: URL) async throws -> Data
    func send(request: URLRequest) async throws
}

struct NetworkAdapterImpl: NetworkAdapter {

    let session: URLSession
    
    init(session: URLSession = URLSession.shared) {
        self.session = session
    }
    
    //MARK: NetworkAdapter Protocol
    
    func fetch(data: Data,  from url: URL) async throws -> Data {
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.badHttpResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.unsuccessfulResponse(code: httpResponse.statusCode)
        }
        
        return data
    }
    
    func send(request: URLRequest) async throws {
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.badHttpResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.unsuccessfulResponse(code: httpResponse.statusCode)
        }
    }

    
    //MARK: Private functions
    
    private func createURL(from endpoint: String) throws -> URL {
        
        guard let url = URL(string: endpoint) else {
            throw NetworkError.badURL
        }
        
        return url
    }
    
}
