//
// JSONAdapter.swift
// SecureChat  
//
// Created by Simone Barbara on 09/10/2025.                               
// All Rights Reserved.                                                         

import Foundation

protocol JSONAdapter {
    func serialize(data: Codable) -> Data?
    func deserialize<T: Decodable>(data: Data) -> T?
}

struct JSONAdapterImpl: JSONAdapter {
    
    func serialize(data: any Codable) -> Data? {
        let encoder = JSONEncoder()
        let encodedData = try? encoder.encode(data)
        return encodedData
    }
    
    func deserialize<T: Decodable>(data: Data) -> T? {
        let decoder = JSONDecoder()
        let message = try? decoder.decode(T.self, from: data)
        return message
    }
    
    
    
    
}
