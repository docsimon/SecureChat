//
//  ChatRepository.swift
//  SecureChat
//
//  Created by Simone Barbara on 02/10/2025.
//

import Foundation

protocol ChatRepositoryProtocol: AnyObject {
    var chatList: [ChatListModel] { get }
    func getMessage(from id: MessageID) -> Message
    func getChat(with id: ChatID) -> Chat?
    func createMessage(with text: String, chatID: ChatID) async
    var delegate: ChatRepositoryDelegate? { get set }
}

protocol ChatRepositoryDelegate: AnyObject {
    func messageUpdated(message: Message)
}

final class ChatRepository: ChatRepositoryProtocol {
    
    let guestRepo: GuestRepositoryProtocol
    let messageRepo: MessageRepositoryProtocol
    weak var delegate: ChatRepositoryDelegate?
    private let notificationCenter: NotificationCenter
    private var db: DatabaseStrategy
    
    static let shared = ChatRepository()
    
    private init(guestRepo: GuestRepositoryProtocol = GuestRepository.shared, messageRepo: MessageRepositoryProtocol = MessageRepository.shared, db: DatabaseStrategy = CustomDB.shared, notificationCenter: NotificationCenter = NotificationCenter.default) {
        self.notificationCenter = notificationCenter
        self.guestRepo = guestRepo
        self.messageRepo = messageRepo
        self.db = db
        registerObserver(for: ChatNotification.newMessage)
    }

    var chatList: [ChatListModel] {
        db.chatList
    }
    
    func getMessage(from id: MessageID) -> Message {
        guard let message = messageRepo.getMessage(with: id) else {
            fatalError("Message cannot be nil")
        }
        return message
    }
    
    func getChat(with id: ChatID) -> Chat? {
        return db.getChat(id: id)
    }
    
    func createMessage(with text: String, chatID: ChatID) {
        messageRepo.createMessage(with: text, chatID: chatID)
    }

    private func sendMessage(message: Message) async {

    }
    
    private func registerObserver(for name: Notification.Name) {
        notificationCenter.addObserver(self, selector: #selector(updateChat), name: name, object: nil)
    }
    
    @objc private func updateChat(_ notification: Notification) {
        guard let message = notification.object as? Message else {
            print("Message is empty!!!")
            return
        }
        delegate?.messageUpdated(message: message)
    }
    
    deinit {
        notificationCenter.removeObserver(self)
    }
   
}
