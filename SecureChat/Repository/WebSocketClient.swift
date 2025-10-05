//
//  WebSocketClient.swift
//  SecureChat
//
//  Created by doc on 05/10/2025.
//
import Foundation

protocol WebSocketClientProtocol {
    func send(message: Message)
    func receive() -> Data?
}

final class WebSocketClient: NSObject, WebSocketClientProtocol, URLSessionDelegate {
    
    private var session: URLSession? = nil
    
    init(session: URLSession?) {
        
        super.init()
        if session == nil {
            self.session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
        }
    }
    
    func receive() -> Data? {
        return nil
    }
    
    func send(message: Message) {
        print("Message \(message.id) sent!")
    }

    
}
