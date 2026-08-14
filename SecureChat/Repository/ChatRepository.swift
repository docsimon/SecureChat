//
//  ChatRepository.swift
//  SecureChat
//
//  Created by Simone Barbara on 02/10/2025.
//

import Foundation

// this protocol must be AnyObject because of the delegate that has to be a class
// otherwise I will use a copy of the repo
protocol ChatRepositoryProtocol: AnyObject {
    var chatList: [ChatListModel] { get }
    func getMessage(from id: MessageID) -> Message
    func getChat(with id: ChatID) -> Chat?
    func createMessage(with text: String, chatID: ChatID) async
    var delegate: ChatRepositoryDelegate? { get set }
    func createChat(title: String)
}

protocol ChatRepositoryDelegate: AnyObject {
    func messageUpdated(message: Message)
}

final class ChatRepository: ChatRepositoryProtocol, ClientDelegate {

    let guestRepo: GuestRepository
    let messageRepo: MessageRepositoryProtocol
    weak var delegate: ChatRepositoryDelegate?
    private let notificationCenter: NotificationCenter
    private var db: DatabaseStrategy
    private let client: ClientProtocol
    private let adapter: JSONAdapter
    
    //static let shared = ChatRepository()
    
    init(guestRepo: GuestRepository,
                 messageRepo: MessageRepositoryProtocol,
                 db: DatabaseStrategy = CustomDB.shared,
                 notificationCenter: NotificationCenter = NotificationCenter.default,
                 client: ClientProtocol = WebsocketClient(),
                 adapter: JSONAdapter = JSONAdapterImpl()) {
        self.notificationCenter = notificationCenter
        self.guestRepo = guestRepo
        self.messageRepo = messageRepo
        self.db = db
        self.client = client
        self.adapter = adapter
        registerObserver(for: ChatNotification.newMessage)
        self.client.delegate = self
    }

    //MARK: ChatRepositoryProtocol
    
    var chatList: [ChatListModel] {
        db.chatList
    }
    
    func getMessage(from id: MessageID) -> Message {
        guard let message = messageRepo.getMessage(with: id) else {
            // TODO: use Logger instead of print
            fatalError("Message cannot be nil")
        }
        return message
    }
    
    func getChat(with id: ChatID) -> Chat? {
        return db.getChat(id: id)
    }
    
    func createMessage(with text: String, chatID: ChatID) {
        let message = messageRepo.createMessage(with: text, chatID: chatID)
        messageRepo.saveMessage(message: message)
        // Send the message to the websocket server
        Task {
            await sendMessage(message: message)
        }
    }
    
    func createChat(title: String) {
        db.createChat(title: title)
    }
    
    //MARK: Client Delegate
    func onReceive(data: Data) {
        do {
            let message: Message = try adapter.deserialize(data: data)
            SCLogger.logger.info(message: "Message received: \(message.content) \(message.date.description)", category: .Message)
            messageRepo.saveMessage(message: message)
        } catch {
            SCLogger.logger.error(message: "Error message", error: error, category: .Message)
        }

    }
    
    func onReceive(message: String) {
        
    }
    
    func onConnectionStatus(status: String) {
        SCLogger.logger.info(message: "WebSocket disconnected: \(status)", category: .Network)
    }
    
    //MARK: Private methods
    
    private func sendMessage(message: Message) async {
        do {
            let data = try adapter.serialize(data: message)
            await client.connect(to: GlobalState.webSocketURL)
            await client.send(data: data)
        } catch {
            SCLogger.logger.error(message: "Error serialising the message", category: .Message)
            return
        }       
    }
    
    private func registerObserver(for name: Notification.Name) {
        notificationCenter.addObserver(self, selector: #selector(updateChat), name: name, object: nil)
    }
    
    /// *************************
    // DO NOT USE IN PRODUCTION
    /// *************************
    // This function changes the message replied by the socket echo server
    #if DEBUG
        private func _updateMessage(message: Message) -> Message {
            
            let ciccio_uuid = UUID(uuidString: "1C89AC13-7991-420D-AFF6-8E06E212613A")
            
            return Message(id: UUID(), chatID: message.chatID, guestID: ciccio_uuid!, isOwner: false, content: message.content, date: message.date, ttl: message.ttl)
        }
    #endif
    
    
    @objc private func updateChat(_ notification: Notification) {
        guard let message = notification.object as? Message else {
            SCLogger.logger.info(message: "Message empty!", category: .Message)
            return
        }
        print("******* GUEST ID: ", message.guestID)
        delegate?.messageUpdated(message: message)
    }
    
    //MARK: Deinit
    
    deinit {
        notificationCenter.removeObserver(self)
    }
   
}
