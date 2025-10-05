//
//  MessageRepository.swift
//  SecureChat
//
//  Created by Simone Barbara on 05/10/2025.
//

protocol MessageRepositoryProtocol {
    func send(message: Message)
}

final class MessageRepository: MessageRepositoryProtocol {

    let client: WebSocketClientProtocol
    
    init(client: WebSocketClientProtocol = WebSocketClient(session: nil)) {
        self.client = client
    }
    
    func send(message: Message) {
        client.send(message: message)
    }
}
