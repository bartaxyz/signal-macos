import Foundation
import SwiftUI
import os

private let logger = Logger(subsystem: "com.signalmacos", category: "store")

func debugLog(_ message: String) {
    logger.info("\(message)")
    // Also write to file for easy access
    let logFile = "/tmp/signal-macos-debug.log"
    let entry = "\(Date()): \(message)\n"
    if let data = entry.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: logFile) {
            if let handle = FileHandle(forWritingAtPath: logFile) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        } else {
            FileManager.default.createFile(atPath: logFile, contents: data)
        }
    }
}

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
        
        Task {
            // Load contacts FIRST (before daemon locks signal-cli data)
            let contacts = await service.loadContacts(account: account)
            debugLog("[SignalStore] Loaded \(contacts.count) contacts")
            // Add "Note to Self" conversation
            if !conversations.contains(where: { $0.id == account }) {
                let selfContact = Contact(id: account, name: "Note to Self")
                conversations.append(Conversation(id: account, contact: selfContact, messages: []))
            }
            
            for contact in contacts {
                guard let number = contact.number, !number.isEmpty else { continue }
                // Skip own number (already added as Note to Self)
                guard number != account else { continue }
                if !conversations.contains(where: { $0.id == number }) {
                    let c = Contact(id: number, name: contact.displayName)
                    conversations.append(Conversation(id: number, contact: c, messages: []))
                }
            }
            debugLog("[SignalStore] Created \(conversations.count) conversations")
            
            // Start receive loop
            service.startReceiveLoop(account: account) { [weak self] envelope in
                Task { @MainActor in
                    self?.handleIncomingEnvelope(envelope)
                }
            }
            debugLog("[SignalStore] Receive loop started")
        }
    }
    
    private func handleIncomingEnvelope(_ signalEnvelope: SignalEnvelope) {
        guard let env = signalEnvelope.envelope else {
            debugLog("[SignalStore] Envelope is nil, skipping")
            return
        }
        debugLog("[SignalStore] Got envelope: source=\(env.source ?? "nil") dataMsg=\(env.dataMessage != nil) syncMsg=\(env.syncMessage != nil)")
        
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
