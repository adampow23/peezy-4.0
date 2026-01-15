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
                            CardView(card: card, isTopCard: index == viewModel.cards.count - 1) { action in
                                viewModel.handleSwipe(card: card, action: action)
                            }
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

                // Top Bar (Undo button when available)
                VStack {
                    HStack {
                        Spacer()
                        if viewModel.canUndo {
                            Button(action: { viewModel.undoLastAction() }) {
                                Image(systemName: "arrow.uturn.backward.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                            .padding()
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

// MARK: - Card View
struct CardView: View {
    let card: PeezyCard
    let isTopCard: Bool
    var onRemove: (SwipeAction) -> Void
    
    @State private var offset: CGSize = .zero
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Glass Material
                RoundedRectangle(cornerRadius: 36)
                    .fill(card.type == .intro ? Color.white : Color.white.opacity(0.9))
                    .shadow(color: Color.black.opacity(0.15), radius: 20, x: 0, y: 10)
                
                // Content
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
                            .foregroundColor(.gray)
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
                            .foregroundColor(.black)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        
                        Text(card.subtitle)
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundColor(.gray)
                            .lineLimit(3)
                    }
                    .padding(.horizontal, 30)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Spacer()
                    
                    // Action Hints
                    if card.type != .intro {
                        HStack {
                            VStack {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.title2)
                                Text(card.laterLabel)
                                    .font(.caption2).bold()
                            }
                            .foregroundColor(.orange)
                            .opacity(0.6)
                            
                            Spacer()
                            
                            VStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title2)
                                Text(card.doItLabel)
                                    .font(.caption2).bold()
                            }
                            .foregroundColor(.green)
                            .opacity(0.6)
                        }
                        .padding(30)
                    } else {
                        HStack {
                            Text("Swipe to Begin")
                                .font(.subheadline).bold()
                                .foregroundColor(.gray.opacity(0.5))
                        }
                        .padding(30)
                    }
                }
            }
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
    
    func swipeAway(width: CGFloat, action: SwipeAction) {
        withAnimation(.easeIn(duration: 0.2)) {
            offset.width = width
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            onRemove(action)
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
    var body: some View {
        VStack {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 80))
                .foregroundStyle(.white.opacity(0.8))
                .padding(.bottom, 20)
            Text("Relax.")
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
    @State private var start = UnitPoint(x: 0, y: -2)
    @State private var end = UnitPoint(x: 4, y: 0)
    
    var body: some View {
        LinearGradient(
            gradient: Gradient(colors: [Color.black, Color(red: 0.1, green: 0.1, blue: 0.2)]),
            startPoint: start,
            endPoint: end
        )
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 5).repeatForever(autoreverses: true)) {
                start = UnitPoint(x: 4, y: 0)
                end = UnitPoint(x: 0, y: 2)
            }
        }
    }
}

// MARK: - Preview
#Preview {
    PeezyStackView(userState: UserState(userId: "preview", name: "Adam"))
}
