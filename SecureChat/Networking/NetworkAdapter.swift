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
    case unsuccessfulResponse(code: Int, payload: Data)
}


protocol NetworkAdapter {
    func fetch(data: Data,  from url: URL) async throws -> Data
    func send(request: URLRequest) async throws -> Data
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
            throw NetworkError.unsuccessfulResponse(code: httpResponse.statusCode + 100, payload: data)
        }
        
        return data
    }
    
    func send(request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.badHttpResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            SCLogger.logger.error(message: "Response error: code: \(httpResponse.statusCode) description: \(httpResponse)", category: .Network)
            throw NetworkError.unsuccessfulResponse(code: httpResponse.statusCode, payload: data)
        }
        
        return data
    }

    
    //MARK: Private functions
    
    private func createURL(from endpoint: String) throws -> URL {
        
        guard let url = URL(string: endpoint) else {
            throw NetworkError.badURL
        }
        
        return url
    }
    
}
