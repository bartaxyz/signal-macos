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
        guard let env = signalEnvelope.envelope,
              let source = env.source,
              let dataMsg = env.dataMessage,
              let body = dataMsg.message else { return }
        
        let timestamp = env.timestamp.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) } ?? Date()
        
        let message = Message(
            timestamp: timestamp,
            body: body,
            sender: source,
            isOutgoing: false
        )
        
        if let idx = conversations.firstIndex(where: { $0.id == source }) {
            conversations[idx].messages.append(message)
        } else {
            let contact = Contact(id: source)
            let conversation = Conversation(id: source, contact: contact, messages: [message])
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
