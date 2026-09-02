//
//  InventoryFlowView.swift
//  Peezy 4.0
//
//  Container view for the inventory scanning flow.
//  Switches on InventorySessionManager.state to present the correct screen.
//  Handles the intro/info task flow cards and the room-saved popup overlay.
//

import SwiftUI

enum InventoryFlowHostingMode {
    case task
    case settings
}

struct InventoryFlowView: View {
    var hostingMode: InventoryFlowHostingMode = .settings
    var onUserDismiss: (() -> Void)? = nil
    var onSubmitted: (() -> Void)? = nil
    var onLater: (() -> Void)? = nil
    var onLocalAnswerChange: ((Bool) -> Void)? = nil
    var dismissesAfterUserAction = true

    @State private var sessionManager = InventorySessionManager()
    @Environment(\.dismiss) private var dismiss

    // Room saved popup
    @State private var showSavedPopup = false
    @State private var savedRoomName = ""
    @State private var savedItemCount = 0
    @State private var showSubmissionComplete = false
    @State private var pendingLockedView = false
    @State private var didFinishInitialLoad = false
    @State private var lastAnswerFingerprint = ""

    private var answerFingerprint: String {
        let rooms = sessionManager.scannedRooms.map { room in
            "\(room.id):\(room.items.count)"
        }
        let coverage = sessionManager.coverageConfirmedRoomIDs.sorted()
        return (rooms + coverage).joined(separator: "|")
    }

    private var hasLocalAnswers: Bool {
        !sessionManager.scannedRooms.isEmpty
            || !sessionManager.coverageConfirmedRoomIDs.isEmpty
    }

    var body: some View {
        ZStack {
            // Main content — switches on state
            Group {
                if sessionManager.submissionStatus == .submitted && !pendingLockedView {
                    InventoryLockedView(
                        sessionManager: sessionManager,
                        onDismiss: {
                            closeFlow()
                        }
                    )
                } else {
                    switch sessionManager.state {

                    // ── Intro Card ──
                    case .intro:
                        introView

                    // ── Info Card ──
                    case .info:
                        infoView

                    // ── Room Hub ──
                    case .roomList, .enteringRoomName:
                        InventoryRoomHubView(
                            sessionManager: sessionManager,
                            onDismiss: {
                                closeFlow()
                            },
                            onSubmitted: {
                                pendingLockedView = true
                                showSubmissionComplete = true
                            },
                            showsDismissControl: hostingMode == .settings
                        )

                    // ── Camera ──
                    case .scanning(let roomName):
                        InventoryCameraView(
                            roomName: roomName,
                            onComplete: { frames, transcript in
                                sessionManager.handleFramesExtracted(
                                    frames,
                                    roomName: roomName,
                                    narration: transcript
                                )
                            },
                            onCancel: {
                                sessionManager.state = .roomList
                            }
                        )

                    // ── Processing ──
                    case .processing(_, let progress):
                        InventoryProcessingView(progressMessage: progress)

                    // ── Item Confirmation ──
                    case .confirming(let roomName, let items, let sessionId):
                        if let userId = sessionManager.userId {
                            InventoryItemConfirmView(
                                items: items,
                                sessionId: sessionId,
                                userId: userId,
                                onComplete: { updatedItems in
                                    sessionManager.handleConfirmationCompleted(updatedItems, roomName: roomName)
                                }
                            )
                        }

                    // ── Room Review ──
                    case .reviewing(let roomName, let items):
                        InventoryRoomReviewView(
                            items: items,
                            roomName: roomName,
                            onConfirm: { confirmedItems in
                                sessionManager.handleReviewConfirmed(confirmedItems, roomName: roomName)
                            },
                            onRescan: {
                                sessionManager.state = .scanning(roomName: roomName)
                            }
                        )

                    // ── Estimate (future) ──
                    case .estimate:
                        InventoryRoomHubView(
                            sessionManager: sessionManager,
                            onDismiss: {
                                closeFlow()
                            },
                            onSubmitted: {
                                pendingLockedView = true
                                showSubmissionComplete = true
                            },
                            showsDismissControl: hostingMode == .settings
                        )
                    }
                }
            }

            // Room saved popup overlay
            if showSavedPopup {
                savedPopupOverlay
            }

            if showsSettingsHostDismissControl {
                settingsHostDismissControl
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: sessionManager.stateDescription)
        .task {
            await sessionManager.loadExistingInventory()
            lastAnswerFingerprint = answerFingerprint
            didFinishInitialLoad = true
        }
        .alert("Submitted!", isPresented: $showSubmissionComplete) {
            Button("Done") {
                pendingLockedView = false
                // Fire the submitted callback immediately so home view knows to refresh.
                onSubmitted?()
            }
        } message: {
            Text("Your inventory has been submitted. It powers your truck size, cost picture, packing plan, and supplies list.")
        }
        .onChange(of: sessionManager.stateDescription) { oldValue, newValue in
            // Detect room save: reviewing → roomList
            if oldValue.hasPrefix("reviewing") && newValue == "roomList" {
                if let lastRoom = sessionManager.scannedRooms.last {
                    savedRoomName = lastRoom.name
                    savedItemCount = lastRoom.items.count
                    withAnimation(.easeOut(duration: 0.3)) {
                        showSavedPopup = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        withAnimation(.easeOut(duration: 0.3)) {
                            showSavedPopup = false
                        }
                    }
                }
            }
        }
        .onChange(of: answerFingerprint) { _, newValue in
            guard didFinishInitialLoad, newValue != lastAnswerFingerprint else { return }
            lastAnswerFingerprint = newValue
            onLocalAnswerChange?(hasLocalAnswers)
        }
        .fullScreenCover(isPresented: movePassPaywallBinding) {
            PaywallGateSheet(surface: .scanner) { subscribed in
                if subscribed {
                    Task { await sessionManager.retryRetainedProcessingRequest() }
                } else {
                    sessionManager.discardRetainedProcessingRequest()
                }
            }
        }
    }

    // MARK: - Intro Card

    private var introView: some View {
        ZStack(alignment: .topTrailing) {
            InteractiveBackground()
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    closeFlow()
                }

            TaskFlowTitleCard(
                taskTitle: "Scan my home",
                icon: "camera.viewfinder",
                onContinue: {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        sessionManager.state = .info
                    }
                },
                onLater: onLater
            )
            .peezyCardChrome()
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 0) {
                PeezyWordmark()
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
        }
    }

    // MARK: - Info Card

    private var infoView: some View {
        ZStack(alignment: .topTrailing) {
            InteractiveBackground()
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    closeFlow()
                }

            TaskFlowInfoCard(
                taskTitle: "Scan my home",
                title: "Here's how it works",
                bodyText: "Pan your camera slowly around each room — about 20 seconds per room. Peezy uses AI (Anthropic Claude) to identify furniture and belongings automatically.\n\nOpen closets and cabinets. Go one room at a time for the best results.\n\nYour scan video frames are sent securely to Anthropic for processing and are not stored or used for AI training. See our Privacy Policy at peezy-1ecrdl.web.app/privacy.html for details.",
                primaryLabel: "Let's go",
                showBack: true,
                onPrimary: {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        sessionManager.state = .roomList
                    }
                },
                onBack: {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        sessionManager.state = .intro
                    }
                }
            )
            .peezyCardChrome()
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 0) {
                PeezyWordmark()
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
        }
    }

    private func closeFlow() {
        onUserDismiss?()
        if dismissesAfterUserAction {
            dismiss()
        }
    }

    private var movePassPaywallBinding: Binding<Bool> {
        Binding(
            get: { sessionManager.movePassRequired },
            set: { isPresented in
                if !isPresented, sessionManager.movePassRequired {
                    sessionManager.discardRetainedProcessingRequest()
                }
            }
        )
    }

    private var showsSettingsHostDismissControl: Bool {
        guard hostingMode == .settings,
              !(sessionManager.submissionStatus == .submitted && !pendingLockedView) else {
            return false
        }

        switch sessionManager.state {
        case .roomList, .enteringRoomName, .estimate:
            return false
        case .intro, .info, .scanning, .processing, .confirming, .reviewing:
            return true
        }
    }

    private var settingsHostDismissControl: some View {
        VStack {
            HStack {
                Spacer()
                Button(action: closeFlow) {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(PeezyTheme.Colors.deepInk)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close scanner")
                .accessibilityIdentifier("inventory.settings.close")
                .padding(.top, 8)
                .padding(.trailing, 12)
            }
            Spacer()
        }
        .zIndex(200)
    }

    // MARK: - Saved Popup

    private var savedPopupOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { }

            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Color(uiColor: .systemGreen))

                Text("Room saved!")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(PeezyTheme.Colors.deepInk)

                Text("\(savedItemCount) items in \(savedRoomName)")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.5))
            }
            .padding(32)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Color.black.opacity(0.1), radius: 20, x: 0, y: 10)
        }
        .transition(.opacity)
        .zIndex(100)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Inventory Flow — Intro") {
    InventoryFlowView()
}
#endif
