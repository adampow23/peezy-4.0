//
//  PeezyWalkthrough.swift
//  Peezy
//
//  Guided walkthrough — spotlight-style tutorial that plays once after paywall.
//  Adapted from Balaji Venkatesh's OneTimeOnBoarding pattern.
//
//  Architecture:
//  - WalkthroughCoordinator: @Observable class collecting spotlight items
//  - WalkthroughItem: model (id, overlay view, mask rect, corner radius)
//  - .walkthroughStep() modifier: marks UI elements to highlight
//  - PeezyWalkthrough<Content>: wrapper view that triggers the overlay
//  - WalkthroughOverlayView: the actual spotlight animation + navigation
//  - WalkthroughStepView: reusable title+body component for step descriptions
//
//  Usage:
//  1. Wrap your root view in PeezyWalkthrough(appStorageID: "PeezyGuidedTour") { ... }
//  2. Add .walkthroughStep(1) { WalkthroughStepView(title:body:) } to each element
//  3. Steps play in order (1, 2, 3...), user taps Next/Back/Skip
//  4. Shows once per device via @AppStorage flag
//
//  Entry point: After paywall completes → main app loads → walkthrough overlay appears
//

import SwiftUI

// MARK: - Walkthrough Step View (Reusable Content Component)

/// Reusable view for walkthrough step descriptions.
/// Keeps styling consistent across all spotlight steps.
struct WalkthroughStepView: View {
    var title: String
    var bodyText: String

    init(title: String, body: String) {
        self.title = title
        self.bodyText = body
    }

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text(bodyText)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .padding(.horizontal, 8)
    }
}

// MARK: - Walkthrough Item Model

fileprivate struct WalkthroughItem: Identifiable {
    var id: Int
    var view: AnyView
    var maskLocation: CGRect
    var cornerRadius: CGFloat
}

// MARK: - Walkthrough Coordinator

@Observable
fileprivate class WalkthroughCoordinator {
    var items: [WalkthroughItem] = []
    var overlayWindow: UIWindow?
    var isFinished: Bool = false

    /// Items sorted by step number
    var orderedItems: [WalkthroughItem] {
        items.sorted { $0.id < $1.id }
    }
}

// MARK: - PeezyWalkthrough Container

struct PeezyWalkthrough<Content: View>: View {
    @AppStorage var hasCompletedWalkthrough: Bool
    var content: Content
    /// Optional async work before the walkthrough animates in (e.g., wait for views to settle)
    var beforeStart: () async -> Void
    var onFinished: () -> Void

    init(
        appStorageID: String = "PeezyGuidedTour",
        @ViewBuilder content: @escaping () -> Content,
        beforeStart: @escaping () async -> Void = {},
        onFinished: @escaping () -> Void = {}
    ) {
        self._hasCompletedWalkthrough = .init(wrappedValue: false, appStorageID)
        self.content = content()
        self.beforeStart = beforeStart
        self.onFinished = onFinished
    }

    fileprivate var coordinator = WalkthroughCoordinator()

    var body: some View {
        content
            .environment(coordinator)
            .task {
                if !hasCompletedWalkthrough {
                    await beforeStart()
                }
                await createOverlayWindow()
            }
            .onChange(of: coordinator.isFinished) { _, newValue in
                if newValue {
                    hasCompletedWalkthrough = true
                    onFinished()
                    hideOverlayWindow()
                }
            }
    }

    // MARK: - Overlay Window Management

    private func createOverlayWindow() async {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              !hasCompletedWalkthrough,
              coordinator.overlayWindow == nil else { return }

        // If a leftover tagged window exists, ensure it's disabled and bail out
        if let existing = scene.windows.first(where: { $0.tag == 1009 }) {
            existing.rootViewController = nil
            existing.isHidden = true
            existing.isUserInteractionEnabled = false
            return
        }

        let window = UIWindow(windowScene: scene)
        window.backgroundColor = .clear
        window.isHidden = false
        window.isUserInteractionEnabled = true
        window.tag = 1009
        coordinator.overlayWindow = window

        // Brief delay so .walkthroughStep modifiers have time to register geometry
        try? await Task.sleep(for: .seconds(0.15))

        guard !coordinator.items.isEmpty else {
            hideOverlayWindow()
            return
        }

        // Snapshot the live screen
        guard let snapshot = snapshotScreen() else {
            hideOverlayWindow()
            return
        }

        let hostController = UIHostingController(
            rootView: WalkthroughOverlayView(snapshot: snapshot)
                .environment(coordinator)
        )
        hostController.view.backgroundColor = .clear
        coordinator.overlayWindow?.rootViewController = hostController
    }

    private func hideOverlayWindow() {
        coordinator.overlayWindow?.rootViewController = nil
        coordinator.overlayWindow?.isHidden = true
        coordinator.overlayWindow?.isUserInteractionEnabled = false
        coordinator.overlayWindow = nil
    }
}

// MARK: - View Modifier for Marking Steps

extension View {
    /// Mark a UI element as a walkthrough spotlight step.
    /// - Parameters:
    ///   - position: Step order (1, 2, 3...)
    ///   - cornerRadius: Corner radius of the spotlight cutout
    ///   - content: The explanatory view shown below the phone mockup
    @ViewBuilder
    func walkthroughStep<Content: View>(
        _ position: Int,
        cornerRadius: CGFloat = 15,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        self.modifier(
            WalkthroughStepSetter(
                position: position,
                cornerRadius: cornerRadius,
                stepContent: content
            )
        )
    }
}

// MARK: - Step Setter Modifier

fileprivate struct WalkthroughStepSetter<StepContent: View>: ViewModifier {
    var position: Int
    var cornerRadius: CGFloat
    @ViewBuilder var stepContent: StepContent

    @Environment(WalkthroughCoordinator.self) var coordinator

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) {
                $0.frame(in: .global)
            } action: { newValue in
                coordinator.items.removeAll(where: { $0.id == position })

                let item = WalkthroughItem(
                    id: position,
                    view: AnyView(stepContent),
                    maskLocation: newValue,
                    cornerRadius: cornerRadius
                )
                coordinator.items.append(item)
            }
            .onDisappear {
                coordinator.items.removeAll(where: { $0.id == position })
            }
    }
}

// MARK: - Overlay View (The Actual Walkthrough UI)

fileprivate struct WalkthroughOverlayView: View {
    var snapshot: UIImage
    @Environment(WalkthroughCoordinator.self) var coordinator

    @State private var animate: Bool = false
    @State private var currentIndex: Int = 0

    // Peezy theme colors
    private let accentColor = Color.white
    private let buttonColor = Color(red: 0.15, green: 0.15, blue: 0.17) // charcoal
    private let buttonTextColor = Color.white

    var body: some View {
        GeometryReader { geo in
            let safeArea = geo.safeAreaInsets
            let isHomeButton = safeArea.bottom == 0
            let deviceCorner: CGFloat = isHomeButton ? 15 : 35

            ZStack {
                // Full black background
                Rectangle()
                    .fill(.black)

                // Snapshot with spotlight mask
                Image(uiImage: snapshot)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .overlay {
                        Rectangle()
                            .fill(.black.opacity(0.55))
                            .reverseMask(alignment: .topLeading) {
                                if !orderedItems.isEmpty {
                                    let mask = orderedItems[currentIndex].maskLocation
                                    let radius = orderedItems[currentIndex].cornerRadius

                                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                                        .frame(width: mask.width, height: mask.height)
                                        .offset(x: mask.minX, y: mask.minY)
                                }
                            }
                            .opacity(animate ? 1 : 0)
                    }
                    .clipShape(.rect(cornerRadius: animate ? deviceCorner : 0, style: .circular))
                    .overlay {
                        deviceFrame(safeArea)
                    }
                    .scaleEffect(animate ? 0.65 : 1, anchor: .top)
                    .offset(y: animate ? safeArea.top + 25 : 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(alignment: .bottom) {
                        bottomControls(safeArea)
                    }
            }
            .ignoresSafeArea()
        }
        .onAppear {
            guard !animate else { return }
            withAnimation(.smooth(duration: 0.35, extraBounce: 0)) {
                animate = true
            }
        }
    }

    // MARK: - Device Frame Overlay

    @ViewBuilder
    private func deviceFrame(_ safeArea: EdgeInsets) -> some View {
        let isHomeButton = safeArea.bottom == 0
        let corner: CGFloat = isHomeButton ? 20 : 45

        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: animate ? corner : 0, style: .continuous)
                .stroke(.white, lineWidth: animate ? 15 : 0)
                .padding(-6)

            // Dynamic Island (non-home-button iPhones)
            if safeArea.bottom != 0 {
                Capsule()
                    .fill(.black)
                    .frame(width: 120, height: 40)
                    .offset(y: 20)
                    .opacity(animate ? 1 : 0)
            }
        }
    }

    // MARK: - Bottom Controls (Copy + Navigation)

    @ViewBuilder
    private func bottomControls(_ safeArea: EdgeInsets) -> some View {
        VStack(spacing: 12) {
            // Step indicator dots
            HStack(spacing: 8) {
                ForEach(0..<orderedItems.count, id: \.self) { index in
                    Circle()
                        .fill(index == currentIndex ? .white : .white.opacity(0.3))
                        .frame(width: 8, height: 8)
                        .scaleEffect(index == currentIndex ? 1.2 : 1.0)
                        .animation(.easeInOut(duration: 0.2), value: currentIndex)
                }
            }
            .padding(.bottom, 4)

            // Step content (swaps per spotlight)
            ZStack {
                ForEach(orderedItems) { item in
                    if currentIndex == orderedItems.firstIndex(where: { $0.id == item.id }) {
                        item.view
                            .transition(.blurReplace)
                            .environment(\.colorScheme, .dark)
                    }
                }
            }
            .frame(minHeight: 80)
            .frame(maxWidth: 300)

            // Navigation buttons
            HStack(spacing: 8) {
                // Back button
                if currentIndex > 0 {
                    Button {
                        withAnimation(.smooth(duration: 0.35, extraBounce: 0)) {
                            currentIndex = max(currentIndex - 1, 0)
                        }
                    } label: {
                        Image(systemName: "chevron.left.circle.fill")
                            .font(.system(size: 38))
                            .foregroundStyle(.white, .gray.opacity(0.4))
                    }
                }

                // Next / Finish button
                Button {
                    if currentIndex == orderedItems.count - 1 {
                        closeWalkthrough()
                    } else {
                        withAnimation(.smooth(duration: 0.35, extraBounce: 0)) {
                            currentIndex += 1
                        }
                    }
                } label: {
                    Text(currentIndex == orderedItems.count - 1 ? "Let's Go" : "Next")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .contentTransition(.numericText())
                        .foregroundStyle(buttonTextColor)
                        .padding(.vertical, 12)
                        .background(buttonColor, in: .capsule)
                        .overlay {
                            Capsule()
                                .stroke(.white.opacity(0.2), lineWidth: 1)
                        }
                }
            }
            .frame(maxWidth: 260)
            .frame(height: 50)
            .padding(.leading, currentIndex > 0 ? -45 : 0)

            // Skip
            Button(action: closeWalkthrough) {
                Text("Skip Tour")
                    .font(.callout)
                    .underline()
            }
            .foregroundStyle(.gray)
        }
        .padding(.horizontal, 15)
        .padding(.bottom, safeArea.bottom + 10)
    }

    // MARK: - Close

    private func closeWalkthrough() {
        withAnimation(.easeInOut(duration: 0.25), completionCriteria: .removed) {
            animate = false
        } completion: {
            coordinator.isFinished = true
        }
        // Fallback: if animation completion doesn't fire, force finish after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if !coordinator.isFinished {
                coordinator.isFinished = true
            }
        }
    }

    var orderedItems: [WalkthroughItem] {
        coordinator.orderedItems
    }
}

// MARK: - Utilities

extension View {
    /// Snapshot the current key window
    fileprivate func snapshotScreen() -> UIImage? {
        guard let window = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.keyWindow else {
            return nil
        }
        let renderer = UIGraphicsImageRenderer(size: window.bounds.size)
        return renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
    }

    /// Reverse mask — cuts out the content shape from self
    @ViewBuilder
    fileprivate func reverseMask<Content: View>(
        alignment: Alignment = .center,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        self.mask {
            Rectangle()
                .overlay(alignment: alignment) {
                    content()
                        .blendMode(.destinationOut)
                }
        }
    }
}
