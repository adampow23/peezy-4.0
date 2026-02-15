import SwiftUI

// MARK: - ChatView
struct ChatView: View {
    var userState: UserState?
    var card: PeezyCard?

    @State private var messages: [ChatMessage] = []
    @State private var inputText: String = ""
    @State private var isLoading: Bool = false
    @State private var error: String?
    @State private var animatingMessageId: String? = nil
    @State private var displayedCharacterCount: Int = 0
    @State private var messageFeedback: [String: Bool] = [:]
    @State private var welcomeMessageId: String?

    @FocusState private var isInputFocused: Bool

    private let client = PeezyClient.shared

    var body: some View {
        ZStack {
            // Breathing Mesh Background
            ChatBackground()

            VStack(spacing: 0) {
                // Header
                ChatHeader()

                // Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(messages) { message in
                                MessageBubble(
                                    message: message,
                                    isAnimating: message.id == animatingMessageId,
                                    displayedCharacterCount: message.id == animatingMessageId ? displayedCharacterCount : message.content.count,
                                    showFeedback: message.role == .assistant && message.id != welcomeMessageId,
                                    feedback: messageFeedback[message.id],
                                    onFeedback: { value in
                                        if let value {
                                            messageFeedback[message.id] = value
                                        } else {
                                            messageFeedback.removeValue(forKey: message.id)
                                        }
                                    }
                                )
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
                    .onChange(of: displayedCharacterCount) { _, _ in
                        if animatingMessageId != nil {
                            scrollToBottom(proxy: proxy)
                        }
                    }
                }

                // Error banner
                if let error = error {
                    ErrorBanner(message: error) {
                        self.error = nil
                    }
                }

                // AI disclaimer
                Text("Peezy can make mistakes")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.3))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)

                // Input bar
                ChatInputBar(
                    text: $inputText,
                    isLoading: isLoading,
                    isFocused: $isInputFocused,
                    onSend: sendMessage
                )
            }
        }
        .onAppear {
            addWelcomeMessage()
        }
        #if DEBUG
        .onReceive(NotificationCenter.default.publisher(for: .debugClearChatHistory)) { _ in
            messages.removeAll()
            addWelcomeMessage()
            print("DEBUG: ChatView cleared messages via notification")
        }
        #endif
    }

    // MARK: - Actions

    private func addWelcomeMessage() {
        guard messages.isEmpty else { return }

        let greeting: String
        if let card = card, !card.title.isEmpty {
            if let name = userState?.name, !name.isEmpty {
                greeting = "Hey \(name)! Let's talk about \(card.title). What questions do you have?"
            } else {
                greeting = "Let's talk about \(card.title). What questions do you have?"
            }
        } else if let name = userState?.name, !name.isEmpty {
            greeting = "Hey \(name)! What's on your mind about the move?"
        } else {
            greeting = "Hey! What's on your mind about the move?"
        }

        let welcomeMessage = ChatMessage(
            role: .assistant,
            content: greeting
        )
        welcomeMessageId = welcomeMessage.id
        messages.append(welcomeMessage)
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
                conversationHistory: messages,
                currentTaskId: card?.id,
                requestType: "chat"
            )

            let assistantMessage = ChatMessage(
                role: .assistant,
                content: response.text
            )

            await MainActor.run {
                messages.append(assistantMessage)
                isLoading = false
                animatingMessageId = assistantMessage.id
                displayedCharacterCount = 0
            }

            let totalCharacters = response.text.count
            let messageId = assistantMessage.id

            while await MainActor.run(body: {
                displayedCharacterCount < totalCharacters && animatingMessageId == messageId
            }) {
                try? await Task.sleep(nanoseconds: 18_000_000) // ~18ms
                await MainActor.run {
                    guard animatingMessageId == messageId else { return }
                    displayedCharacterCount = min(displayedCharacterCount + 2, totalCharacters)
                    if displayedCharacterCount >= totalCharacters {
                        animatingMessageId = nil
                    }
                }
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

// MARK: - Chat Background (Breathing Mesh)
struct ChatBackground: View {
    @State private var animate = false

    var body: some View {
        ZStack {
            // Deep Space Base
            Color(red: 0.02, green: 0.02, blue: 0.06)
                .ignoresSafeArea()

            // Moving Orbs (Atmosphere)
            GeometryReader { geo in
                ZStack {
                    // Orb 1: Intelligence (Deep Navy/Purple)
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(red: 0.1, green: 0.1, blue: 0.25).opacity(0.6),
                                    Color(red: 0.1, green: 0.1, blue: 0.25).opacity(0)
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: geo.size.width * 0.5
                            )
                        )
                        .frame(width: geo.size.width * 1.2)
                        .blur(radius: 60)
                        .offset(
                            x: animate ? -80 : 80,
                            y: animate ? -150 : 100
                        )

                    // Orb 2: Energy (Deep Purple/Violet)
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(red: 0.18, green: 0.1, blue: 0.3).opacity(0.5),
                                    Color(red: 0.18, green: 0.1, blue: 0.3).opacity(0)
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: geo.size.width * 0.5
                            )
                        )
                        .frame(width: geo.size.width * 1.0)
                        .blur(radius: 50)
                        .offset(
                            x: animate ? 120 : -120,
                            y: animate ? 250 : -80
                        )

                    // Orb 3: Subtle Teal accent
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(red: 0.05, green: 0.2, blue: 0.25).opacity(0.3),
                                    Color(red: 0.05, green: 0.2, blue: 0.25).opacity(0)
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: geo.size.width * 0.4
                            )
                        )
                        .frame(width: geo.size.width * 0.8)
                        .blur(radius: 40)
                        .offset(
                            x: animate ? -50 : 100,
                            y: animate ? 400 : 200
                        )
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 12).repeatForever(autoreverses: true)) {
                animate.toggle()
            }
        }
    }
}

// MARK: - Chat Header (Floating Glass Panel)
struct ChatHeader: View {
    @Environment(\.dismiss) private var dismiss

    // Charcoal color for glass tint
    private let charcoalColor = Color(red: 0.15, green: 0.15, blue: 0.17)

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Peezy")
                    .font(.headline)
                    .foregroundColor(.white)
                Text("Your moving concierge")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
            }

            Spacer()

            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            ZStack {
                // Glass blur effect
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)

                // Charcoal tint
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(charcoalColor.opacity(0.6))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 5)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}

// MARK: - Message Bubble (Charcoal Glass Style)
struct MessageBubble: View {
    let message: ChatMessage
    var isAnimating: Bool = false
    var displayedCharacterCount: Int = 0
    var showFeedback: Bool = false
    var feedback: Bool? = nil
    var onFeedback: ((Bool?) -> Void)? = nil

    // Charcoal color for assistant bubbles
    private let charcoalColor = Color(red: 0.15, green: 0.15, blue: 0.17)

    private var displayedText: String {
        if isAnimating {
            return String(message.content.prefix(displayedCharacterCount))
        }
        return message.content
    }

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 60)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(displayedText)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        ZStack {
                            if message.role == .user {
                                // User bubble: Solid blue with subtle gradient
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color(red: 0.2, green: 0.5, blue: 1.0),
                                                Color(red: 0.15, green: 0.4, blue: 0.9)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            } else {
                                // Assistant bubble: Charcoal glass
                                ZStack {
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .fill(.ultraThinMaterial)

                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .fill(charcoalColor.opacity(0.6))
                                }
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                            }
                        }
                    )
                    .foregroundColor(.white)

                // Feedback buttons for non-welcome assistant messages
                if showFeedback && message.role == .assistant {
                    HStack(spacing: 12) {
                        Button {
                            if feedback == true {
                                onFeedback?(nil)
                            } else {
                                onFeedback?(true)
                            }
                        } label: {
                            Image(systemName: feedback == true ? "hand.thumbsup.fill" : "hand.thumbsup")
                                .font(.system(size: 13))
                                .foregroundColor(feedback == true ? .white.opacity(0.9) : .white.opacity(0.35))
                        }
                        .buttonStyle(.plain)

                        Button {
                            if feedback == false {
                                onFeedback?(nil)
                            } else {
                                onFeedback?(false)
                            }
                        } label: {
                            Image(systemName: feedback == false ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                                .font(.system(size: 13))
                                .foregroundColor(feedback == false ? .white.opacity(0.9) : .white.opacity(0.35))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.leading, 12)
                    .padding(.top, 2)
                }
            }

            if message.role == .assistant {
                Spacer(minLength: 60)
            }
        }
    }
}

// MARK: - Chat Input Bar (Floating Glass Panel)
struct ChatInputBar: View {
    @Binding var text: String
    let isLoading: Bool
    var isFocused: FocusState<Bool>.Binding
    let onSend: () -> Void

    // Charcoal color for glass tint
    private let charcoalColor = Color(red: 0.15, green: 0.15, blue: 0.17)

    var body: some View {
        HStack(spacing: 12) {
            // Text field with charcoal glass background
            TextField("Ask Peezy anything...", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .foregroundColor(.white)
                .tint(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(charcoalColor.opacity(0.4))
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .lineLimit(1...5)
                .focused(isFocused)
                .onSubmit(onSend)

            // Send button
            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(canSend ? Color(red: 0.2, green: 0.5, blue: 1.0) : .white.opacity(0.3))
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            ZStack {
                // Glass blur effect
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.ultraThinMaterial)

                // Charcoal tint
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(charcoalColor.opacity(0.6))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: -5)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
    }
}

// MARK: - Typing Indicator (Charcoal Glass Style)
struct TypingIndicator: View {
    @State private var animating = false

    // Charcoal color for glass tint
    private let charcoalColor = Color(red: 0.15, green: 0.15, blue: 0.17)

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.white.opacity(0.6))
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
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)

                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(charcoalColor.opacity(0.6))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .onAppear { animating = true }
    }
}

// MARK: - Error Banner (Charcoal Glass Style)
struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    // Charcoal color for glass tint
    private let charcoalColor = Color(red: 0.15, green: 0.15, blue: 0.17)

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.white)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .padding()
        .background(
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)

                Rectangle()
                    .fill(charcoalColor.opacity(0.6))
            }
        )
    }
}

// MARK: - Preview
#Preview {
    ChatView(userState: UserState(userId: "preview", name: "Kierstin"))
}
