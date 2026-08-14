import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import Observation
import SwiftUI
import UserNotifications

struct SupportChatView: View {
    let chatService: SupportChatService
    var taskContext: SupportTaskContext?

    @State private var inputText = ""
    @State private var showsNotificationPermissionMoment = false
    @AppStorage("supportNotificationPermissionMomentShown") private var notificationPermissionMomentShown = false
    @FocusState private var isInputFocused: Bool

    private let deepInk = PeezyTheme.Colors.deepInk

    init(
        chatService: SupportChatService,
        taskContext: SupportTaskContext? = nil
    ) {
        self.chatService = chatService
        self.taskContext = taskContext
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if chatService.messages.isEmpty {
                Spacer()
                emptyState
                Spacer()
            } else {
                messageList
            }

            if let error = chatService.error {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(PeezyTheme.Colors.emotionalRed)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 6)
                    .accessibilityIdentifier("support.error")
            }

            composer
        }
        .background(
            InteractiveBackground()
                .ignoresSafeArea()
        )
        .onAppear {
            chatService.startListening()
            markMessagesReadAndClearBadge()
        }
        .onChange(of: chatService.unreadCount) { _, unreadCount in
            if unreadCount > 0 {
                markMessagesReadAndClearBadge()
            }
        }
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text("Message us")
                .font(.title2.bold())
                .foregroundStyle(deepInk)
                .multilineTextAlignment(.center)

            Text("A real person on the Peezy team reads every message.")
                .font(PeezyTheme.Typography.caption)
                .foregroundStyle(deepInk.opacity(0.55))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 52)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("support.header")
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(deepInk.opacity(0.22))
                .accessibilityHidden(true)

            Text("Send us a message whenever you need help.")
                .font(PeezyTheme.Typography.body)
                .foregroundStyle(deepInk.opacity(0.58))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
        .accessibilityIdentifier("support.empty_state")
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(chatService.messages) { message in
                        messageBubble(message)
                            .id(message.id)
                    }

                    if showsNotificationPermissionMoment {
                        notificationPermissionCard
                            .id("support-notification-permission")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: chatService.messages.count) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: showsNotificationPermissionMoment) { _, isShowing in
                guard isShowing else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("support-notification-permission", anchor: .bottom)
                }
            }
            .onAppear {
                scrollToBottom(proxy, animated: false)
            }
        }
    }

    private func messageBubble(_ message: SupportMessage) -> some View {
        HStack {
            if message.isFromUser {
                Spacer(minLength: 60)
            }

            VStack(alignment: message.isFromUser ? .trailing : .leading, spacing: 4) {
                Text(message.text)
                    .font(PeezyTheme.Typography.body)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background {
                        if message.isFromUser {
                            RoundedRectangle(
                                cornerRadius: PeezyTheme.Layout.cornerRadiusLarge,
                                style: .continuous
                            )
                            .fill(deepInk)
                        } else {
                            supportBubbleBackground
                        }
                    }
                    .foregroundStyle(message.isFromUser ? PeezyTheme.Colors.lightBase : deepInk)
                    .accessibilityLabel("\(message.isFromUser ? "You" : "Support"): \(message.text)")
                    .accessibilityIdentifier("support.message")

                Text(formattedTime(message.timestamp))
                    .font(.caption2)
                    .foregroundStyle(deepInk.opacity(0.38))
                    .padding(.horizontal, 4)
                    .accessibilityIdentifier("support.message_time")

                if message.id == latestUserMessageId {
                    let receipt = chatService.receipt(for: message)
                    Text(receipt.caption)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(deepInk.opacity(0.52))
                        .padding(.horizontal, 4)
                        .accessibilityLabel("Message status: \(receipt.caption)")
                        .accessibilityIdentifier("support.receipt_caption")
                }
            }

            if !message.isFromUser {
                Spacer(minLength: 60)
            }
        }
    }

    private var supportBubbleBackground: some View {
        ZStack {
            RoundedRectangle(
                cornerRadius: PeezyTheme.Layout.cornerRadiusLarge,
                style: .continuous
            )
            .fill(.regularMaterial)
            RoundedRectangle(
                cornerRadius: PeezyTheme.Layout.cornerRadiusLarge,
                style: .continuous
            )
            .fill(Color.white.opacity(0.15))
        }
        .overlay {
            RoundedRectangle(
                cornerRadius: PeezyTheme.Layout.cornerRadiusLarge,
                style: .continuous
            )
            .stroke(Color.black.opacity(0.05), lineWidth: 1)
        }
    }

    private var notificationPermissionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Text("Want a heads-up when we reply?")
                    .font(PeezyTheme.Typography.body.weight(.semibold))
                    .foregroundStyle(deepInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("support.notification_prompt_title")

                Spacer(minLength: 8)

                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        showsNotificationPermissionMoment = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.bold())
                        .foregroundStyle(deepInk.opacity(0.5))
                        .frame(width: 28, height: 28)
                }
                .accessibilityLabel("Not now")
                .accessibilityIdentifier("support.notification_prompt_dismiss")
            }

            Button("Turn on notifications") {
                withAnimation(.easeOut(duration: 0.2)) {
                    showsNotificationPermissionMoment = false
                }
                PushNotificationAuthorization.request()
            }
            .buttonStyle(.borderedProminent)
            .tint(deepInk)
            .accessibilityIdentifier("support.notification_prompt_enable")
        }
        .padding(16)
        .background(supportBubbleBackground)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("support.notification_prompt")
    }

    private var composer: some View {
        HStack(spacing: 12) {
            TextField("Message us", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .foregroundStyle(deepInk)
                .tint(deepInk)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.white.opacity(0.15))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.black.opacity(0.05), lineWidth: 1)
                }
                .lineLimit(1...5)
                .focused($isInputFocused)
                .submitLabel(.send)
                .onSubmit { send() }
                .accessibilityIdentifier("support.composer")

            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(canSend ? deepInk : deepInk.opacity(0.3))
                    .frame(width: 44, height: 44)
            }
            .disabled(!canSend)
            .accessibilityLabel("Send message")
            .accessibilityIdentifier("support.send_button")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.regularMaterial)
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.white.opacity(0.15))
            }
        )
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.1), radius: 12, x: 0, y: -5)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var latestUserMessageId: String? {
        chatService.messages.last(where: { $0.isFromUser })?.id
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""

        Task {
            let wasFirstUserMessage = await chatService.sendMessage(text, taskContext: taskContext)
            guard wasFirstUserMessage, !notificationPermissionMomentShown else { return }

            notificationPermissionMomentShown = true
            withAnimation(.easeOut(duration: 0.2)) {
                showsNotificationPermissionMoment = true
            }
        }
    }

    private func markMessagesReadAndClearBadge() {
        chatService.markSupportMessagesRead()
        Task {
            try? await UNUserNotificationCenter.current().setBadgeCount(0)
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        guard let lastId = chatService.messages.last?.id else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(lastId, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(lastId, anchor: .bottom)
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

enum PeezyChatSurface {
    case support
    case task(taskId: String, title: String)

    var chatId: String {
        switch self {
        case .support:
            "support"
        case .task(let taskId, _):
            taskId
        }
    }

    var headerTitle: String {
        switch self {
        case .support:
            "Ask Peezy"
        case .task(_, let title):
            "Chat about \(title)"
        }
    }

    var headerSubtitle: String {
        switch self {
        case .support:
            "Ask about your move, tasks, access, or purchases."
        case .task:
            "Peezy uses this task and any saved research as context."
        }
    }

    var emptyPrompt: String {
        switch self {
        case .support:
            "Ask a question about your move or how Peezy works."
        case .task:
            "Ask about the choices, details, or research for this task."
        }
    }

    var inputPlaceholder: String {
        switch self {
        case .support:
            "Ask Peezy"
        case .task:
            "Ask about this task"
        }
    }

    fileprivate func callablePayload(message: String) -> [String: Any] {
        switch self {
        case .support:
            ["surface": "support", "message": message]
        case .task(let taskId, _):
            ["surface": "task", "taskId": taskId, "message": message]
        }
    }
}

struct PeezyChatView: View {
    let surface: PeezyChatSurface

    @State private var model: PeezyChatViewModel
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool

    private let deepInk = PeezyTheme.Colors.deepInk

    init(surface: PeezyChatSurface) {
        self.surface = surface
        _model = State(initialValue: PeezyChatViewModel(surface: surface))
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if model.isLoading {
                ProgressView("Loading chat…")
                    .tint(deepInk)
                    .foregroundStyle(deepInk)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.messages.isEmpty && !model.isSending {
                Spacer()
                emptyState
                Spacer()
            } else {
                messageList
            }

            if let errorMessage = model.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(PeezyTheme.Colors.emotionalRed)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 6)
                    .accessibilityIdentifier("chat_error_message")
            }

            composer
        }
        .background(
            InteractiveBackground()
                .ignoresSafeArea()
        )
        .onAppear {
            model.startListening()
        }
        .onDisappear {
            model.stopListening()
        }
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text(surface.headerTitle)
                .font(.title2.bold())
                .foregroundStyle(deepInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(surface.headerSubtitle)
                .font(PeezyTheme.Typography.caption)
                .foregroundStyle(deepInk.opacity(0.55))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 52)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("support_header")
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(deepInk.opacity(0.22))
                .accessibilityHidden(true)

            Text(surface.emptyPrompt)
                .font(PeezyTheme.Typography.body)
                .foregroundStyle(deepInk.opacity(0.58))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(model.messages) { message in
                        messageBubble(message)
                            .id(message.id)
                    }

                    if model.isSending {
                        thinkingBubble
                            .id("peezy-thinking")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: model.messages.count) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: model.isSending) { _, isSending in
                if isSending {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("peezy-thinking", anchor: .bottom)
                    }
                } else {
                    scrollToBottom(proxy)
                }
            }
            .onAppear {
                scrollToBottom(proxy, animated: false)
            }
        }
    }

    private func messageBubble(_ message: PeezyChatMessage) -> some View {
        HStack {
            if message.isFromUser {
                Spacer(minLength: 60)
            }

            VStack(alignment: message.isFromUser ? .trailing : .leading, spacing: 4) {
                Text(message.text)
                    .font(PeezyTheme.Typography.body)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background {
                        if message.isFromUser {
                            RoundedRectangle(
                                cornerRadius: PeezyTheme.Layout.cornerRadiusLarge,
                                style: .continuous
                            )
                            .fill(deepInk)
                        } else {
                            assistantBubbleBackground
                        }
                    }
                    .foregroundStyle(message.isFromUser ? PeezyTheme.Colors.lightBase : deepInk)

                Text(formattedTime(message.timestamp))
                    .font(.caption2)
                    .foregroundStyle(deepInk.opacity(0.38))
                    .padding(.horizontal, 4)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(message.isFromUser ? "You" : "Peezy"): \(message.text)")

            if !message.isFromUser {
                Spacer(minLength: 60)
            }
        }
    }

    private var thinkingBubble: some View {
        HStack {
            HStack(spacing: 10) {
                ProgressView()
                    .tint(deepInk)
                Text("Peezy is thinking…")
                    .font(PeezyTheme.Typography.body)
                    .foregroundStyle(deepInk.opacity(0.7))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background {
                assistantBubbleBackground
            }

            Spacer(minLength: 60)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Peezy is thinking")
    }

    private var assistantBubbleBackground: some View {
        ZStack {
            RoundedRectangle(
                cornerRadius: PeezyTheme.Layout.cornerRadiusLarge,
                style: .continuous
            )
            .fill(.regularMaterial)
            RoundedRectangle(
                cornerRadius: PeezyTheme.Layout.cornerRadiusLarge,
                style: .continuous
            )
            .fill(Color.white.opacity(0.15))
        }
        .overlay {
            RoundedRectangle(
                cornerRadius: PeezyTheme.Layout.cornerRadiusLarge,
                style: .continuous
            )
            .stroke(Color.black.opacity(0.05), lineWidth: 1)
        }
    }

    private var composer: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                TextField(surface.inputPlaceholder, text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .foregroundStyle(deepInk)
                    .tint(deepInk)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.white.opacity(0.15))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.black.opacity(0.05), lineWidth: 1)
                    }
                    .lineLimit(1...5)
                    .focused($isInputFocused)
                    .submitLabel(.send)
                    .onSubmit { send() }
                    .accessibilityIdentifier("chat_input_field")

                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(canSend ? deepInk : deepInk.opacity(0.3))
                        .frame(width: 44, height: 44)
                }
                .disabled(!canSend)
                .accessibilityLabel("Send message")
                .accessibilityIdentifier("chat_send_button")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(.regularMaterial)
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Color.white.opacity(0.15))
                }
            )
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.black.opacity(0.05), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.1), radius: 12, x: 0, y: -5)

            Text("Peezy can make mistakes. Double-check anything important.")
                .font(.caption2)
                .foregroundStyle(deepInk.opacity(0.52))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("chat_disclaimer")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !model.isSending
    }

    private func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !model.isSending else { return }
        inputText = ""
        Task {
            await model.send(text)
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        guard let lastId = model.messages.last?.id else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(lastId, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(lastId, anchor: .bottom)
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

private struct PeezyChatMessage: Identifiable {
    let id: String
    let text: String
    let sender: Sender
    let timestamp: Date

    enum Sender: String {
        case user
        case assistant
    }

    var isFromUser: Bool {
        sender == .user
    }

    nonisolated init?(document: QueryDocumentSnapshot) {
        let data = document.data()
        guard let text = data["text"] as? String,
              !text.isEmpty,
              let senderValue = data["sender"] as? String,
              let sender = Sender(rawValue: senderValue),
              let timestamp = data["timestamp"] as? Timestamp else { return nil }

        self.id = document.documentID
        self.text = text
        self.sender = sender
        self.timestamp = timestamp.dateValue()
    }
}

@MainActor
@Observable
private final class PeezyChatViewModel {
    private(set) var messages: [PeezyChatMessage] = []
    private(set) var isLoading = true
    private(set) var isSending = false
    private(set) var errorMessage: String?

    @ObservationIgnored private let surface: PeezyChatSurface
    @ObservationIgnored private let db = Firestore.firestore()
    @ObservationIgnored private var listener: ListenerRegistration?

    init(surface: PeezyChatSurface) {
        self.surface = surface
    }

    func startListening() {
        guard listener == nil else { return }
        guard let userId = Auth.auth().currentUser?.uid else {
            isLoading = false
            errorMessage = "Sign in to use chat."
            return
        }

        listener = db.collection("users").document(userId)
            .collection("chats").document(surface.chatId)
            .collection("messages")
            .order(by: "timestamp", descending: false)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.isLoading = false

                    if error != nil {
                        self.errorMessage = "Peezy couldn't load this chat. Try again."
                        return
                    }

                    self.errorMessage = nil
                    self.messages = snapshot?.documents.compactMap(PeezyChatMessage.init(document:)) ?? []
                }
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }

    func send(_ message: String) async {
        guard Auth.auth().currentUser != nil else {
            errorMessage = "Sign in to use chat."
            return
        }
        guard !isSending else { return }

        isSending = true
        errorMessage = nil
        defer { isSending = false }

        do {
            _ = try await Functions.functions()
                .httpsCallable("peezyChat")
                .call(surface.callablePayload(message: message))
        } catch {
            errorMessage = "Peezy couldn't answer that right now. Try again."
        }
    }
}

#Preview {
    SupportChatView(chatService: SupportChatService())
}
