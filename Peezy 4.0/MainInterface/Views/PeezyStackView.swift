import SwiftUI
import UIKit

// MARK: - The Main View
struct PeezyStackView: View {
    // ViewModel manages all state and backend communication
    // Can be passed in externally (for workflow integration) or created internally
    @State private var _internalViewModel: PeezyStackViewModel?
    private var externalViewModel: PeezyStackViewModel?

    var viewModel: PeezyStackViewModel {
        externalViewModel ?? (_internalViewModel ?? PeezyStackViewModel())
    }

    // User state passed in from parent (from assessment)
    var userState: UserState?

    // Init for standalone use (creates own viewModel)
    init(userState: UserState? = nil) {
        self.userState = userState
        self.externalViewModel = nil
    }

    // Init for use with external viewModel (workflow integration)
    init(viewModel: PeezyStackViewModel, userState: UserState? = nil) {
        self.externalViewModel = viewModel
        self.userState = userState
    }
    
    // Chat sheet
    @State private var showChat = false

    #if DEBUG
    @State private var showDebugMenu = false
    #endif
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                InteractiveBackground()

                // Loading State
                if viewModel.isLoading && viewModel.cards.isEmpty {
                    LoadingView()
                }

                // Empty State (All caught up!)
                else if viewModel.cards.isEmpty {
                    EmptyStateView()
                }

                // The Stack
                VStack {
                    Spacer()
                    ZStack {
                        ForEach(Array(viewModel.cards.enumerated()), id: \.element.id) { index, card in
                            CardView(
                                card: card,
                                isTopCard: index == viewModel.cards.count - 1,
                                onRemove: { action in
                                    viewModel.handleSwipe(card: card, action: action)
                                },
                                updateCount: viewModel.updateCount,
                                taskCount: viewModel.taskCount
                            )
                            .scaleEffect(scale(for: index))
                            .offset(y: yOffset(for: index))
                            .opacity(index == viewModel.cards.count - 1 ? 1.0 : 0.6)
                            .allowsHitTesting(index == viewModel.cards.count - 1)
                            .zIndex(Double(index))
                        }
                    }
                    .frame(height: 520)
                    .padding(.bottom, 50)
                    Spacer()
                }

                // Swipe Up Detection Zone (bottom half of screen)
                VStack {
                    Spacer()
                    Color.clear
                        .frame(height: geometry.size.height * 0.5)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 50)
                                .onEnded { gesture in
                                    // Detect upward swipe (negative Y = up)
                                    // Require more vertical than horizontal movement
                                    let verticalMovement = gesture.translation.height
                                    let horizontalMovement = abs(gesture.translation.width)

                                    // Swipe up: at least 80pt upward, and more vertical than horizontal
                                    if verticalMovement < -80 && abs(verticalMovement) > horizontalMovement {
                                        showChat = true
                                    }
                                }
                        )
                }

                // Top Bar (Logo + Undo button)
                VStack(spacing: 0) {
                    // Peezy Logo - positioned close to Dynamic Island/camera area
                    Text("peezy")
                        .font(.system(size: 18, weight: .light, design: .default))
                        .tracking(6)
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                        #if DEBUG
                        .onTapGesture(count: 3) {
                            showDebugMenu = true
                        }
                        #endif

                    // Undo button row (below logo)
                    HStack {
                        Spacer()
                        if viewModel.canUndo {
                            Button(action: { viewModel.undoLastAction() }) {
                                Image(systemName: "arrow.uturn.backward.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                            .padding(.trailing, 16)
                            .padding(.top, 8)
                        }
                    }

                    Spacer()
                }

                // Bottom Handle (opens chat on tap)
                VStack {
                    Spacer()
                    Button(action: { showChat = true }) {
                        VStack(spacing: 4) {
                            Image(systemName: "chevron.up")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.3))
                            Capsule()
                                .fill(.ultraThinMaterial)
                                .frame(width: 60, height: 6)
                            Text("Swipe up to chat")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.4))
                        }
                        .padding(.bottom, 10)
                    }
                }

                // Error Toast
                if let error = viewModel.error {
                    VStack {
                        Spacer()
                        ErrorToast(message: error.localizedDescription) {
                            viewModel.error = nil
                        }
                        .padding(.bottom, 80)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .onAppear {
            // Create internal viewModel if not using external one
            if externalViewModel == nil && _internalViewModel == nil {
                _internalViewModel = PeezyStackViewModel()
            }

            // Pass user state to view model
            viewModel.userState = userState

            // Load cards from backend
            Task {
                await viewModel.loadInitialCards()
            }
        }
        .refreshable {
            await viewModel.refreshCards()
        }
        .sheet(isPresented: $showChat) {
            ChatView(userState: userState)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        #if DEBUG
        .sheet(isPresented: $showDebugMenu) {
            DebugMenuView(viewModel: viewModel)
        }
        #endif
    }
    
    // MARK: - Stack Physics
    func scale(for index: Int) -> CGFloat {
        let offset = viewModel.cards.count - 1 - index
        return 1.0 - (CGFloat(offset) * 0.05)
    }
    
    func yOffset(for index: Int) -> CGFloat {
        let offset = viewModel.cards.count - 1 - index
        return CGFloat(offset) * 25
    }
}

// MARK: - Card View (Charcoal Glass Style)
struct CardView: View {
    let card: PeezyCard
    let isTopCard: Bool
    var onRemove: (SwipeAction) -> Void

    // Counts for intro card display (optional)
    var updateCount: Int = 0
    var taskCount: Int = 0

    @State private var offset: CGSize = .zero

    // The specific "Text Input" Charcoal Gray
    private let charcoalColor = Color(red: 0.15, green: 0.15, blue: 0.17)

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 1. THE GLASS STACK
                ZStack {
                    // A. The Blur Effect (Apple's native glass material)
                    RoundedRectangle(cornerRadius: 36, style: .continuous)
                        .foregroundStyle(.ultraThinMaterial)

                    // B. The Charcoal Tint (Semi-transparent)
                    RoundedRectangle(cornerRadius: 36, style: .continuous)
                        .fill(charcoalColor.opacity(isTopCard ? 0.6 : 0.8))
                }
                // C. The Edge Highlight (Makes it look premium)
                .overlay(
                    RoundedRectangle(cornerRadius: 36, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    // Inset slightly to avoid harsh edges
                        .padding(1)
                )
                // D. Deep Shadow for 3D depth
                .shadow(color: Color.black.opacity(0.4), radius: 20, x: 0, y: 15)


                // 2. THE CONTENT
                if card.type == .intro {
                    // INTRO CARD - Title Page Layout
                    introCardContent
                } else {
                    // STANDARD CARD - Original Layout
                    standardCardContent
                }
            }
            // Gesture and rotation logic remains the same...
            .rotationEffect(.degrees(Double(offset.width / 20)))
            .offset(x: offset.width, y: offset.height * 0.4)
            .gesture(
                DragGesture()
                    .onChanged { gesture in
                        if isTopCard {
                            offset = gesture.translation
                        }
                    }
                    .onEnded { _ in
                        if offset.width > 100 {
                            swipeAway(width: geometry.size.width + 100, action: .doIt)
                        } else if offset.width < -100 {
                            swipeAway(width: -(geometry.size.width + 100), action: .later)
                        } else {
                            withAnimation(.spring()) { offset = .zero }
                        }
                    }
            )
        }
        .frame(width: 340, height: 500)
    }

    // MARK: - Intro Card Content (Matches Task Card Style)
    private var introCardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()

            // Main content area - same positioning as task cards
            VStack(alignment: .leading, spacing: 15) {
                // Greeting as main title (same style as "Internet")
                Text(greetingText)
                    .font(.system(size: 48, weight: .heavy))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)

                // Thin accent divider
                Rectangle()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 50, height: 2)

                // Task summary as subtitle (warm briefing message)
                Text(taskSummaryText)
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(4)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 30)
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()
        }
    }

    // Helper to build the greeting text
    private var greetingText: String {
        if card.subtitle.isEmpty {
            return "\(card.title)."
        } else {
            return "\(card.title) \(card.subtitle)."
        }
    }

    // Helper to build the task summary text (warm, conversational briefing)
    // Uses the card's briefingMessage if available, otherwise generates a fallback
    private var taskSummaryText: String {
        // Use card's custom briefing if available
        if let briefing = card.briefingMessage, !briefing.isEmpty {
            return briefing
        }

        // Fallback: generate a warm message based on counts
        return fallbackBriefingMessage
    }

    // Fallback briefing when card doesn't have a custom message
    // Should feel like a happy, eager assistant
    private var fallbackBriefingMessage: String {
        let updates = updateCount
        let tasks = taskCount

        // All caught up
        if updates == 0 && tasks == 0 {
            return "All clear! I'll let you know when something comes up."
        }

        // Generate warm, eager fallback
        if tasks == 1 && updates == 0 {
            return "Just one thing today - need your input so I can take care of it for you."
        } else if tasks == 2 && updates == 0 {
            return "Couple things for you today - shouldn't take long!"
        } else if updates == 1 && tasks == 0 {
            return "Got an update for you!"
        } else if updates > 0 && tasks > 0 {
            return "Got some updates, plus a few things I need your input on."
        } else if tasks > 2 {
            return "Got a few things ready for you."
        }

        return "Got a few things ready for you."
    }

    // MARK: - Standard Card Content
    private var standardCardContent: some View {
        VStack(spacing: 0) {
            // Dynamic Header
            ZStack {
                // Default State
                if offset.width == 0 {
                    HStack {
                        Image(systemName: card.icon)
                        Text(card.headerLabel)
                        Spacer()
                    }
                    .font(.caption).bold()
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.top, 30)
                    .padding(.horizontal, 30)
                }

                // "LATER" Label (Left Drag)
                if offset.width < -20 {
                    Text(card.laterLabel.uppercased())
                        .font(.system(size: 60, weight: .black))
                        .foregroundStyle(.orange.gradient)
                        .opacity(Double(abs(offset.width) / 100))
                }

                // "DO IT" Label (Right Drag)
                if offset.width > 20 {
                    Text(card.doItLabel.uppercased())
                        .font(.system(size: 60, weight: .black))
                        .foregroundStyle(.green.gradient)
                        .opacity(Double(abs(offset.width) / 100))
                }
            }
            .frame(height: 80)

            Spacer()

            // Main Content
            VStack(alignment: .leading, spacing: 15) {
                Text(card.title)
                    .font(.system(size: 48, weight: .heavy))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                Text(card.subtitle)
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(3)
            }
            .padding(.horizontal, 30)
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            // Action Hints
            HStack {
                // Later (Left)
                VStack {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.title2)
                    Text(card.laterLabel)
                        .font(.caption2).bold()
                }
                .foregroundColor(.orange)
                .opacity(0.8)

                Spacer()

                // Do It (Right)
                VStack {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                    Text(card.doItLabel)
                        .font(.caption2).bold()
                }
                .foregroundColor(.green)
                .opacity(0.8)
            }
            .padding(30)
        }
    }

    func swipeAway(width: CGFloat, action: SwipeAction) {
        withAnimation(.easeIn(duration: 0.2)) {
            offset.width = width
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            onRemove(action)
        }
    }
}

// MARK: - Summary Row (for intro card)
struct SummaryRow: View {
    let count: Int
    let label: String
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
                .frame(width: 24)

            Text("\(count) \(label)\(count == 1 ? "" : "s")")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
        }
    }
}

// MARK: - Supporting Views
struct LoadingView: View {
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.white)
            Text("Loading your tasks...")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.8))
        }
    }
}

struct EmptyStateView: View {
    private var timeOfDay: TimeOfDay { TimeOfDay.current }

    var body: some View {
        VStack(spacing: 16) {
            // Time-dependent icon
            timeOfDay.emptyStateIconStyle
                .font(.system(size: 80))
                .padding(.bottom, 4)

            // Time-dependent headline
            Text(timeOfDay.emptyStateHeadline)
                .font(.largeTitle).bold()
                .foregroundStyle(.white)

            Text("You're all caught up.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
        }
    }
}

struct ErrorToast: View {
    let message: String
    let onDismiss: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(message)
                .font(.caption)
                .lineLimit(2)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

struct InteractiveBackground: View {
    @State private var animate = false

    // Time-dependent colors
    private var timeOfDay: TimeOfDay { TimeOfDay.current }
    private var baseColor: Color { timeOfDay.baseColor }
    private var orbColors: (primary: Color, secondary: Color, accent: Color) { timeOfDay.orbColors }

    var body: some View {
        ZStack {
            // 1. The Deep Space Base (time-dependent)
            baseColor
                .ignoresSafeArea()

            // 2. The Moving Orbs (Atmosphere) - colors vary by time of day
            GeometryReader { geo in
                ZStack {
                    // Orb 1: Primary color
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    orbColors.primary.opacity(0.6),
                                    orbColors.primary.opacity(0)
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

                    // Orb 2: Secondary color
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    orbColors.secondary.opacity(0.5),
                                    orbColors.secondary.opacity(0)
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

                    // Orb 3: Accent color
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    orbColors.accent.opacity(0.3),
                                    orbColors.accent.opacity(0)
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

// MARK: - Preview
#Preview {
    PeezyStackView(userState: UserState(userId: "preview", name: "Kierstin"))
}
