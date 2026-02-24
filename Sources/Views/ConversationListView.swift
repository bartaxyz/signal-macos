import SwiftUI

struct ConversationListView: View {
    @Environment(SignalStore.self) private var store
    @State private var showingContacts = false
    
    var body: some View {
        @Bindable var store = store
        
        List(selection: $store.selectedConversationID) {
            if activeConversations.isEmpty {
                ContentUnavailableView {
                    Label("No Conversations", systemImage: "bubble.left")
                } description: {
                    Text("Send a message from your phone or tap + to start a new conversation")
                }
            } else {
                ForEach(activeConversations) { conversation in
                    ConversationRow(conversation: conversation)
                        .tag(conversation.id)
                }
            }
        }
        .navigationTitle("Signal")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingContacts = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
            }
        }
        .sheet(isPresented: $showingContacts) {
            ContactListView()
        }
    }
    
    /// Only show conversations that have messages
    private var activeConversations: [Conversation] {
        store.conversations
            .filter { !$0.messages.isEmpty }
            .sorted { $0.lastMessageDate > $1.lastMessageDate }
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

struct ContactListView: View {
    @Environment(SignalStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredContacts, id: \.id) { conversation in
                    Button {
                        store.selectedConversationID = conversation.id
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(conversation.contact.displayName)
                                .fontWeight(.medium)
                            if conversation.contact.name != nil {
                                Text(conversation.id)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .searchable(text: $searchText, prompt: "Search contacts")
            .navigationTitle("New Conversation")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .frame(minWidth: 350, minHeight: 400)
    }
    
    private var filteredContacts: [Conversation] {
        let all = store.conversations.sorted { 
            $0.contact.displayName.localizedCompare($1.contact.displayName) == .orderedAscending 
        }
        if searchText.isEmpty { return all }
        return all.filter {
            $0.contact.displayName.localizedCaseInsensitiveContains(searchText) ||
            $0.id.contains(searchText)
        }
    }
}
