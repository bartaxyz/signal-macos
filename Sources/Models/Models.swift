import Foundation

struct Contact: Identifiable, Hashable, Sendable {
    let id: String // phone number
    var name: String?
    
    var displayName: String {
        name ?? id
    }
}

struct Message: Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let body: String
    let sender: String // phone number
    let isOutgoing: Bool
    
    init(id: UUID = UUID(), timestamp: Date = Date(), body: String, sender: String, isOutgoing: Bool) {
        self.id = id
        self.timestamp = timestamp
        self.body = body
        self.sender = sender
        self.isOutgoing = isOutgoing
    }
}

struct Conversation: Identifiable, Sendable {
    let id: String // phone number or group id
    var contact: Contact
    var messages: [Message]
    
    var lastMessage: Message? { messages.last }
    
    var lastMessagePreview: String {
        lastMessage?.body ?? "No messages"
    }
    
    var lastMessageDate: Date {
        lastMessage?.timestamp ?? .distantPast
    }
}
