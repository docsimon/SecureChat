////
////  CustomDB.swift
////  SecureChat
////
////  Created by Simone Barbara on 06/10/2025.
////
//
import Foundation
//
//final class CustomDB: DatabaseStrategy {
//
//    static let shared = CustomDB()
//    private var guestDict = [GuestID: Guest]()
//    private var chatDict = [ChatID: Chat]()
//    private var messageDict = [MessageID: Message]()
//    private let notificationCenter: NotificationCenter
//    
//    init(notificationCenter: NotificationCenter = NotificationCenter.default) {
//        self.notificationCenter = notificationCenter
//        createMockGuests()
//        createMockChats()
//        createMockMessages()
//    }
//    
//    //MARK: DatabaseStrategy
//    
//    func saveChat(chat: Chat) {
//        let chatID = chat.id
//        chatDict[chatID] = chat
//    }
//    
//    func saveGuest(guest: Guest) {
//        let guestID = guest.id
//        guestDict[guestID] = guest
//    }
//    
//    func saveMessage(message: Message) {
//        let messageID = message.id
//        // Update Message Dictionary
//        messageDict[messageID] = message
//        // Update Chat Dictionary
//        chatDict[message.chatID]?.messages.append(messageID)
//        // Send notification to subscribers (currently only ChatRepository)
//        notificationCenter.post(Notification(name: ChatNotification.newMessage, object: message))
//    }
//
//    func getMessage(id: MessageID) -> Message? {
//        return messageDict[id]
//    }
//    
//    func getGuest(id: GuestID) -> Guest? {
//        return guestDict[id]
//    }
//    
//    func getChat(id: ChatID) -> Chat? {
//        return chatDict[id]
//    }
//    
//    var chatList: [ChatListModel] {
//        let chatList =
//        chatDict
//            .sorted { $0.value.date < $1.value.date }
//            .map { $0.1 }
//            .map { ChatListModel(chatID: $0.id, title: $0.title, date: $0.date)}
//        return chatList
//    }
//    
//    func bootstrap() throws {
//        
//    }
//    
//    func createChat(title: String) {
//        
//    }
//    
//    func getOwner() throws -> UUID {
//        return UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
//    }
//
//    
//    private func createMockGuests() {
//        let guests = [
//        Guest(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, username: "Simone"),
//        Guest(id: UUID(uuidString: "987fcdeb-1234-5678-9012-34567890abcd")!, username: "Ciccio"),
//        Guest(id: UUID(uuidString: "550e8400-e29b-41d4-a716-446655440000")!, username: "Formaggio"),
//        Guest(id: UUID(uuidString: "6ba7b810-9dad-11d1-80b4-00c04fd430c8")!, username: "Cippalippa"),
//        Guest(id: UUID(uuidString: "f47ac10b-58cc-4372-a567-0e02b2c3d479")!, username: "Charlie"),
//        Guest(id: UUID(uuidString: "1b671a64-40d5-491e-99b0-da01ff1f3341")!, username: "Topasky")]
//        
//        for guest in guests {
//            guestDict[guest.id] = guest
//        }
//    }
//    
//    private func createMockChats() {
//        
//        chatDict = [
//            UUID(uuidString: "578E8708-36DC-4820-86DF-4CB00A1EC8C8")!: Chat(id: UUID(uuidString: "578E8708-36DC-4820-86DF-4CB00A1EC8C8")!, title: "Chat 1",
//                guests: [UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, UUID(uuidString: "987fcdeb-1234-5678-9012-34567890abcd")!],
//                messages: [UUID(uuidString: "00000000-240E-4025-81E3-16B29B6333A7")!, UUID(uuidString: "00000001-240E-4025-81E3-16B29B6333A7")!],
//                date: Date.now),
//            
//            UUID(uuidString: "CA654CF5-862E-4FDA-8856-35B67564A07B")!: Chat(id: UUID(uuidString: "CA654CF5-862E-4FDA-8856-35B67564A07B")!, title: "Chat 2", guests: [UUID(uuidString: "550e8400-e29b-41d4-a716-446655440000")!, UUID(uuidString: "6ba7b810-9dad-11d1-80b4-00c04fd430c8")!], messages: [UUID(uuidString: "00000002-240E-4025-81E3-16B29B6333A7")!, UUID(uuidString: "00000003-240E-4025-81E3-16B29B6333A7")!], date: Date.now),
//            
//            UUID(uuidString: "73B44F3D-240E-4025-81E3-16B29B6333A7")!: Chat(id: UUID(uuidString: "73B44F3D-240E-4025-81E3-16B29B6333A7")!, title: "Chat3", guests: [UUID(uuidString: "f47ac10b-58cc-4372-a567-0e02b2c3d479")!, UUID(uuidString: "1b671a64-40d5-491e-99b0-da01ff1f3341")!], messages: [UUID(uuidString: "00000004-240E-4025-81E3-16B29B6333A7")!, UUID(uuidString: "00000005-240E-4025-81E3-16B29B6333A7")!], date: Date.now)
//        ]
//    }
//    
//    private func createMockMessages() {
//        let messages = [
//            Message(id: UUID(uuidString: "00000000-240E-4025-81E3-16B29B6333A7")!, chatID: UUID(uuidString: "578E8708-36DC-4820-86DF-4CB00A1EC8C8")!, guestID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, isOwner: true, content: "content of message 1, ciao come stai?", date: Date(), ttl: 10),
//            Message(id: UUID(uuidString: "00000001-240E-4025-81E3-16B29B6333A7")!, chatID: UUID(uuidString: "578E8708-36DC-4820-86DF-4CB00A1EC8C8")!, guestID: UUID(uuidString: "987fcdeb-1234-5678-9012-34567890abcd")!, isOwner: false, content: "content of message 2, bene grazie, tu?", date: Date(), ttl: 10),
//            Message(id: UUID(uuidString: "00000002-240E-4025-81E3-16B29B6333A7")!, chatID: UUID(uuidString: "CA654CF5-862E-4FDA-8856-35B67564A07B")!, guestID: UUID(uuidString: "550e8400-e29b-41d4-a716-446655440000")!, isOwner: true, content: "content of message 3", date: Date(), ttl: 10),
//            Message(id: UUID(uuidString: "00000003-240E-4025-81E3-16B29B6333A7")!, chatID: UUID(uuidString: "CA654CF5-862E-4FDA-8856-35B67564A07B")!, guestID: UUID(uuidString: "6ba7b810-9dad-11d1-80b4-00c04fd430c8")!, isOwner: true, content: "content of message 4", date: Date(), ttl: 10),
//            Message(id: UUID(uuidString: "00000004-240E-4025-81E3-16B29B6333A7")!, chatID: UUID(uuidString: "73B44F3D-240E-4025-81E3-16B29B6333A7")!, guestID: UUID(uuidString: "f47ac10b-58cc-4372-a567-0e02b2c3d479")!, isOwner: true, content: "content of message 5", date: Date(), ttl: 10),
//            Message(id: UUID(uuidString: "00000005-240E-4025-81E3-16B29B6333A7")!, chatID: UUID(uuidString: "73B44F3D-240E-4025-81E3-16B29B6333A7")!, guestID:  UUID(uuidString: "1b671a64-40d5-491e-99b0-da01ff1f3341")!, isOwner: true, content: "content of message 6", date: Date(), ttl: 10)
//        ]
//        
//        for message in messages {
//            messageDict[message.id] = message
//        }
//    }
//}

final class CustomDB: DatabaseStrategy {
    func update(guest: Guest) {
        
    }
    
    func getOwner() throws -> Guest {
        return mockGuest()
    }
    
    func getGuest(id: GuestID) throws -> Guest {
        throw NSError()
    }
    
    func addGuest(guest: Guest) {
        
    }
    
    
    static let shared = CustomDB()
    
    func saveChat(chat: Chat) {
        
    }
    
    func saveGuest(guest: Guest) {
        
    }
    
    func saveMessage(message: Message) {
        
    }
    
    func getMessage(id: MessageID) -> Message? {
        nil
    }
    
    func getGuest(id: GuestID) -> Guest? {
        nil
    }
    
    func getChat(id: ChatID) -> Chat? {
        nil
    }
    
    let chatList: [ChatListModel] = []
    
    func bootstrap() throws {
        
    }
    
    func createChat(title: String) {
        
    }
    
    func getOwner() throws -> UUID {
        UUID()
    }
    
    
    private func mockGuest() -> Guest {
        
        return Guest(id: UUID(), username: "test", isOwner: false, date: Date(), isRegistered: false)
    }
        
}
