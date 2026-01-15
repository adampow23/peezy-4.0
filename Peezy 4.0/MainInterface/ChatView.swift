import SwiftUI

// MARK: - ChatView
struct ChatView: View {
    var userState: UserState?
    
    @State private var messages: [ChatMessage] = []
    @State private var inputText: String = ""
    @State private var isLoading: Bool = false
    @State private var error: String?
    
    @FocusState private var isInputFocused: Bool
    
    private let client = PeezyClient.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            ChatHeader()
            
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                        
                        // Loading indicator
                        if isLoading {
                            HStack {
                                TypingIndicator()
                                Spacer()
                            }
                            .padding(.horizontal)
                            .id("loading")
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: isLoading) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
            }
            
            // Error banner
            if let error = error {
                ErrorBanner(message: error) {
                    self.error = nil
                }
            }
            
            // Input bar
            ChatInputBar(
                text: $inputText,
                isLoading: isLoading,
                isFocused: $isInputFocused,
                onSend: sendMessage
            )
        }
        .background(Color(.systemGroupedBackground))
        .onAppear {
            addWelcomeMessage()
        }
    }
    
    // MARK: - Actions
    
    private func addWelcomeMessage() {
        guard messages.isEmpty else { return }
        
        let greeting: String
        if let name = userState?.name, !name.isEmpty {
            greeting = "Hey \(name)! What's on your mind about the move?"
        } else {
            greeting = "Hey! What's on your mind about the move?"
        }
        
        messages.append(ChatMessage(
            role: .assistant,
            content: greeting
        ))
    }
    
    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        
        // Add user message
        let userMessage = ChatMessage(role: .user, content: text)
        messages.append(userMessage)
        inputText = ""
        
        // Call backend
        Task {
            await sendToBackend(text)
        }
    }
    
    private func sendToBackend(_ text: String) async {
        await MainActor.run {
            isLoading = true
            error = nil
        }
        
        do {
            let response = try await client.sendMessage(
                text,
                userState: userState ?? UserState(userId: "unknown", name: ""),
                conversationHistory: messages
            )
            
            await MainActor.run {
                messages.append(ChatMessage(
                    role: .assistant,
                    content: response.text
                ))
                isLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = "Couldn't reach Peezy. Try again?"
                isLoading = false
            }
        }
    }
    
    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            if isLoading {
                proxy.scrollTo("loading", anchor: .bottom)
            } else if let lastMessage = messages.last {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }
}

// MARK: - Chat Header
struct ChatHeader: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Peezy")
                    .font(.headline)
                Text("Your moving concierge")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.bar)
    }
}

// MARK: - Message Bubble
struct MessageBubble: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 60)
            }
            
            Text(message.content)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(backgroundColor)
                .foregroundColor(foregroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 20))
            
            if message.role == .assistant {
                Spacer(minLength: 60)
            }
        }
    }
    
    private var backgroundColor: Color {
        message.role == .user ? .blue : Color(.systemGray5)
    }
    
    private var foregroundColor: Color {
        message.role == .user ? .white : .primary
    }
}

// MARK: - Chat Input Bar
struct ChatInputBar: View {
    @Binding var text: String
    let isLoading: Bool
    var isFocused: FocusState<Bool>.Binding
    let onSend: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            TextField("Ask Peezy anything...", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .lineLimit(1...5)
                .focused(isFocused)
                .onSubmit(onSend)
            
            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(canSend ? .blue : .gray)
            }
            .disabled(!canSend)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
    
    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
    }
}

// MARK: - Typing Indicator
struct TypingIndicator: View {
    @State private var animating = false
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.gray)
                    .frame(width: 8, height: 8)
                    .scaleEffect(animating ? 1.0 : 0.5)
                    .animation(
                        .easeInOut(duration: 0.6)
                        .repeatForever()
                        .delay(Double(index) * 0.2),
                        value: animating
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemGray5))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .onAppear { animating = true }
    }
}

// MARK: - Error Banner
struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(message)
                .font(.subheadline)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
    }
}

// MARK: - Preview
#Preview {
    ChatView(userState: UserState(userId: "preview", name: "Adam"))
}
