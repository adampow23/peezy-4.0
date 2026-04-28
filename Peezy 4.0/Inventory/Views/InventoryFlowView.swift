//
//  InventoryFlowView.swift
//  Peezy 4.0
//
//  Container view for the inventory scanning flow.
//  Switches on InventorySessionManager.state to present the correct screen.
//  Handles the intro/info task flow cards and the room-saved popup overlay.
//

import SwiftUI

struct InventoryFlowView: View {
    var onUserDismiss: (() -> Void)? = nil
    var onSubmitted: (() -> Void)? = nil
    var onLater: (() -> Void)? = nil

    @State private var sessionManager = InventorySessionManager()
    @Environment(\.dismiss) private var dismiss

    // Room saved popup
    @State private var showSavedPopup = false
    @State private var savedRoomName = ""
    @State private var savedItemCount = 0
    @State private var showSubmissionComplete = false
    @State private var pendingLockedView = false

    var body: some View {
        ZStack {
            // Main content — switches on state
            Group {
                if sessionManager.submissionStatus == .submitted && !pendingLockedView {
                    InventoryLockedView(
                        rooms: sessionManager.scannedRooms,
                        onDismiss: {
                            onUserDismiss?()
                            dismiss()
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
                                onUserDismiss?()
                                dismiss()
                            },
                            onSubmitted: {
                                pendingLockedView = true
                                showSubmissionComplete = true
                            }
                        )

                    // ── Camera ──
                    case .scanning(let roomName):
                        InventoryCameraView(
                            roomName: roomName,
                            onComplete: { frames in
                                Task {
                                    await sessionManager.handleFramesExtracted(frames, roomName: roomName)
                                }
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
                                onUserDismiss?()
                                dismiss()
                            },
                            onSubmitted: {
                                pendingLockedView = true
                                showSubmissionComplete = true
                            }
                        )
                    }
                }
            }

            // Room saved popup overlay
            if showSavedPopup {
                savedPopupOverlay
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: sessionManager.stateDescription)
        .task {
            await sessionManager.loadExistingInventory()
        }
        .alert("Submitted!", isPresented: $showSubmissionComplete) {
            Button("Done") {
                pendingLockedView = false
                // Fire the submitted callback immediately so home view knows to refresh.
                onSubmitted?()
            }
        } message: {
            Text("Your inventory has been submitted. We'll use it to coordinate your move.")
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
        dismiss()
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
