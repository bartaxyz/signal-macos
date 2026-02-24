import SwiftUI

struct ConversationListView: View {
    @Environment(SignalStore.self) private var store
    
    var body: some View {
        @Bindable var store = store
        
        List(selection: $store.selectedConversationID) {
            if store.conversations.isEmpty {
                ContentUnavailableView {
                    Label("No Conversations", systemImage: "bubble.left")
                } description: {
                    Text("Messages will appear here")
                }
            } else {
                ForEach(sortedConversations) { conversation in
                    ConversationRow(conversation: conversation)
                        .tag(conversation.id)
                }
            }
        }
        .navigationTitle("Signal")
    }
    
    private var sortedConversations: [Conversation] {
        store.conversations.sorted { $0.lastMessageDate > $1.lastMessageDate }
    }
}

struct ConversationRow: View {
    let conversation: Conversation
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(conversation.contact.displayName)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                
                Spacer()
                
                if let date = conversation.lastMessage?.timestamp {
                    Text(date, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Text(conversation.lastMessagePreview)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }
}
