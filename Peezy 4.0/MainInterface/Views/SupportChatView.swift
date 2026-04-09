import SwiftUI

struct SupportChatView: View {
    var userState: UserState?

    @State private var service = SupportChatService()
    @State private var inputText: String = ""
    @FocusState private var isInputFocused: Bool

    private let deepInk = PeezyTheme.Colors.deepInk

    var body: some View {
        VStack(spacing: 0) {
            header

            if service.messages.isEmpty {
                Spacer()
                emptyState
                Spacer()
            } else {
                messageList
            }

            inputBar
        }
        .background(
            InteractiveBackground()
                .ignoresSafeArea()
        )
        .onAppear {
            service.startListening()
            service.markSupportMessagesRead()
        }
        .onDisappear {
            service.stopListening()
        }
        .onChange(of: service.messages.count) { _, _ in
            service.markSupportMessagesRead()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 4) {
            Text("Support")
                .font(.title2.bold())
                .foregroundStyle(deepInk)

            Text("We typically respond within a few hours")
                .font(PeezyTheme.Typography.caption)
                .foregroundStyle(deepInk.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(deepInk.opacity(0.2))

            Text("Questions? Feedback?\nWe're here to help.")
                .font(PeezyTheme.Typography.body)
                .foregroundStyle(deepInk.opacity(0.4))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(service.messages) { message in
                        messageBubble(message)
                            .id(message.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onChange(of: service.messages.count) { _, _ in
                if let lastId = service.messages.last?.id {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
            .onAppear {
                if let lastId = service.messages.last?.id {
                    proxy.scrollTo(lastId, anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Message Bubble

    private func messageBubble(_ message: SupportMessage) -> some View {
        HStack {
            if message.isFromUser { Spacer(minLength: 60) }

            VStack(alignment: message.isFromUser ? .trailing : .leading, spacing: 4) {
                Text(message.text)
                    .font(PeezyTheme.Typography.body)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        Group {
                            if message.isFromUser {
                                RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadiusLarge, style: .continuous)
                                    .fill(deepInk)
                            } else {
                                ZStack {
                                    RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadiusLarge, style: .continuous)
                                        .fill(.regularMaterial)
                                    RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadiusLarge, style: .continuous)
                                        .fill(Color.white.opacity(0.15))
                                }
                                .overlay(
                                    RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadiusLarge, style: .continuous)
                                        .stroke(Color.black.opacity(0.05), lineWidth: 1)
                                )
                            }
                        }
                    )
                    .foregroundStyle(message.isFromUser ? PeezyTheme.Colors.lightBase : deepInk)

                Text(formattedTime(message.timestamp))
                    .font(.system(size: 10))
                    .foregroundStyle(deepInk.opacity(0.3))
                    .padding(.horizontal, 4)
            }

            if !message.isFromUser { Spacer(minLength: 60) }
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 12) {
            TextField("Message...", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .foregroundStyle(deepInk)
                .tint(deepInk)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.white.opacity(0.15))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.black.opacity(0.05), lineWidth: 1)
                )
                .lineLimit(1...5)
                .focused($isInputFocused)
                .submitLabel(.send)
                .onSubmit { send() }

            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(canSend ? deepInk : deepInk.opacity(0.3))
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.regularMaterial)
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.white.opacity(0.15))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.1), radius: 12, x: 0, y: -5)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Helpers

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        let text = inputText
        inputText = ""
        Task {
            await service.sendMessage(text)
        }
    }

    private func formattedTime(_ date: Date) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()

        if calendar.isDateInToday(date) {
            formatter.dateFormat = "h:mm a"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            formatter.dateFormat = "MMM d, h:mm a"
        }

        return formatter.string(from: date)
    }
}

#Preview {
    SupportChatView(userState: .preview)
}
