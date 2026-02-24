import Foundation
import SwiftUI

enum LinkingState: Sendable {
    case idle
    case generatingQR
    case waitingForScan(uri: String)
    case linked
    case failed(String)
}

@MainActor
@Observable
final class SignalStore {
    var conversations: [Conversation] = []
    var selectedConversationID: String?
    var linkedAccount: String?
    var linkingState: LinkingState = .idle
    var draftMessage: String = ""
    
    private let service = SignalCLIService()
    
    var isLinked: Bool { linkedAccount != nil }
    
    var selectedConversation: Conversation? {
        guard let id = selectedConversationID else { return nil }
        return conversations.first { $0.id == id }
    }
    
    init() {
        // Check for existing linked account
        if let account = SignalCLIService.findLinkedAccount() {
            linkedAccount = account
            linkingState = .linked
            startDaemon()
        }
    }
    
    // MARK: - Linking
    
    func startLinking() {
        linkingState = .generatingQR
        
        Task {
            do {
                let uri = try await service.link(deviceName: "Signal macOS")
                linkingState = .waitingForScan(uri: uri)
                
                // Poll for account to appear
                await waitForLinkCompletion()
            } catch {
                linkingState = .failed(error.localizedDescription)
            }
        }
    }
    
    private func waitForLinkCompletion() async {
        for _ in 0..<120 { // Wait up to 2 minutes
            try? await Task.sleep(for: .seconds(1))
            if let account = SignalCLIService.findLinkedAccount() {
                linkedAccount = account
                linkingState = .linked
                startDaemon()
                return
            }
        }
        linkingState = .failed("Linking timed out")
    }
    
    // MARK: - Daemon
    
    func startDaemon() {
        guard let account = linkedAccount else { return }
        
        // Load contacts first
        Task {
            let contacts = await service.loadContacts(account: account)
            for contact in contacts {
                guard let number = contact.number, !number.isEmpty else { continue }
                if !conversations.contains(where: { $0.id == number }) {
                    let c = Contact(id: number, name: contact.name)
                    conversations.append(Conversation(id: number, contact: c, messages: []))
                }
            }
        }
        
        do {
            try service.startDaemon(account: account) { [weak self] envelope in
                Task { @MainActor in
                    self?.handleIncomingEnvelope(envelope)
                }
            }
        } catch {
            print("Failed to start daemon: \(error)")
        }
    }
    
    private func handleIncomingEnvelope(_ signalEnvelope: SignalEnvelope) {
        guard let env = signalEnvelope.envelope else { return }
        
        let body: String
        let conversationID: String
        let isOutgoing: Bool
        let senderName: String?
        
        if let dataMsg = env.dataMessage, let msg = dataMsg.message, let source = env.source {
            // Incoming message from someone else
            body = msg
            conversationID = source
            isOutgoing = false
            senderName = env.sourceName
        } else if let syncMsg = env.syncMessage,
                  let sentMsg = syncMsg.sentMessage,
                  let msg = sentMsg.message,
                  let destination = sentMsg.destination {
            // Sync message: sent from our own phone
            body = msg
            conversationID = destination
            isOutgoing = true
            senderName = sentMsg.destinationName
        } else {
            return
        }
        
        let timestamp = env.timestamp.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) } ?? Date()
        
        let message = Message(
            timestamp: timestamp,
            body: body,
            sender: isOutgoing ? (linkedAccount ?? "") : conversationID,
            isOutgoing: isOutgoing
        )
        
        if let idx = conversations.firstIndex(where: { $0.id == conversationID }) {
            conversations[idx].messages.append(message)
        } else {
            let contact = Contact(id: conversationID, name: senderName)
            let conversation = Conversation(id: conversationID, contact: contact, messages: [message])
            conversations.append(conversation)
        }
    }
    
    // MARK: - Send
    
    func sendMessage(_ text: String, to conversationID: String) {
        guard !text.isEmpty else { return }
        
        let message = Message(
            body: text,
            sender: linkedAccount ?? "",
            isOutgoing: true
        )
        
        if let idx = conversations.firstIndex(where: { $0.id == conversationID }) {
            conversations[idx].messages.append(message)
        }
        
        do {
            try service.send(message: text, to: conversationID)
        } catch {
            print("Send failed: \(error)")
        }
    }
}
