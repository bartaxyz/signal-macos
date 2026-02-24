import SwiftUI

struct ContentView: View {
    @Environment(SignalStore.self) private var store
    
    var body: some View {
        @Bindable var store = store
        
        NavigationSplitView {
            ConversationListView()
                .navigationSplitViewColumnWidth(min: 240, ideal: 280)
        } detail: {
            if let conversationID = store.selectedConversationID,
               let conversation = store.conversations.first(where: { $0.id == conversationID }) {
                MessageView(conversation: conversation)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Select a conversation")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
