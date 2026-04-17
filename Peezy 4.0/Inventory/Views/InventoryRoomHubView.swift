//
//  InventoryRoomHubView.swift
//  Peezy 4.0
//
//  The persistent hub for the inventory scanner.
//  Shows scanned rooms with item counts, scan button, submit/save options.
//  Room name entry via half-sheet.
//

import SwiftUI

struct InventoryRoomHubView: View {
    var sessionManager: InventorySessionManager
    var onDismiss: () -> Void
    var onSubmitted: () -> Void = {}

    @State private var showRoomNameEntry = false
    @State private var newRoomName = ""
    @State private var showDeleteConfirmation = false
    @State private var roomToDelete: ScannedRoom?
    @State private var showSubmitConfirmation = false
    @State private var isSubmitting = false

    var body: some View {
        ZStack {
            InteractiveBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                header
                    .padding(.top, 16)

                // Content
                if sessionManager.scannedRooms.isEmpty {
                    emptyState
                } else {
                    roomList
                }

                Spacer()

                // Bottom buttons
                bottomButtons
                    .padding(.bottom, 20)
            }

            // Close button — top right
            VStack {
                HStack {
                    Spacer()
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.6))
                            .frame(width: 32, height: 32)
                            .background(.regularMaterial.opacity(0.8))
                            .clipShape(Circle())
                    }
                    .padding(.trailing, 20)
                    .padding(.top, 16)
                }
                Spacer()
            }
        }
        .alert("Delete Room", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if let room = roomToDelete,
                   let index = sessionManager.scannedRooms.firstIndex(where: { $0.id == room.id }) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        sessionManager.deleteRoom(at: IndexSet(integer: index))
                    }
                }
                roomToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                roomToDelete = nil
            }
        } message: {
            if let room = roomToDelete {
                Text("Remove \(room.name) and its \(room.items.count) items?")
            }
        }
        .alert("Ready to submit?", isPresented: $showSubmitConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Yes, submit") {
                submitInventory()
            }
        } message: {
            Text("Are you sure you've scanned all your rooms? Once submitted, you won't be able to add or change rooms. If something changes, message us in the chat.")
        }
        .sheet(isPresented: $showRoomNameEntry) {
            roomNameSheet
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 6) {
            Text("Your Inventory")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(PeezyTheme.Colors.deepInk)

            if !sessionManager.scannedRooms.isEmpty {
                let roomCount = sessionManager.scannedRooms.count
                let roomWord = roomCount == 1 ? "room" : "rooms"
                let itemWord = sessionManager.totalItemCount == 1 ? "item" : "items"
                Text("\(roomCount) \(roomWord) · \(sessionManager.totalItemCount) \(itemWord)")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.4))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "camera.viewfinder")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.2))

            Text("Scan your first room to start\nbuilding your inventory")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.4))
                .multilineTextAlignment(.center)

            Spacer()
        }
    }

    // MARK: - Room List

    private var roomList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(sessionManager.scannedRooms) { room in
                    roomRow(room)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
    }

    private func roomRow(_ room: ScannedRoom) -> some View {
        HStack(spacing: 14) {
            // Room info
            VStack(alignment: .leading, spacing: 4) {
                Text(room.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(PeezyTheme.Colors.deepInk)

                let itemWord = room.items.count == 1 ? "item" : "items"
                Text("\(room.items.count) \(itemWord)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.4))
            }

            Spacer()

            // Item count badge
            Text("\(room.items.count)")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(PeezyTheme.Colors.deepInk)
                .frame(width: 34, height: 34)
                .background(PeezyTheme.Colors.deepInk.opacity(0.08))
                .clipShape(Circle())

            // Delete button
            Button {
                PeezyHaptics.light()
                roomToDelete = room
                showDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(uiColor: .systemRed).opacity(0.6))
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.regularMaterial)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.15))
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
            }
        )
    }

    // MARK: - Bottom Buttons

    private var bottomButtons: some View {
        VStack(spacing: 12) {
            // 1. Scan button — ALWAYS visible, ALWAYS primary
            Button {
                PeezyHaptics.light()
                showRoomNameEntry = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 18, weight: .medium))
                    Text(sessionManager.scannedRooms.isEmpty ? "Scan Your First Room" : "Scan Another Room")
                        .font(.system(size: 17, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(height: 54)
                .frame(maxWidth: .infinity)
                .background(PeezyTheme.Colors.deepInk)
                .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
            }
            .buttonStyle(.plain)

            // 2. Submit or save draft — only when rooms exist
            if !sessionManager.scannedRooms.isEmpty {
                VStack(spacing: 12) {
                    PeezyAssessmentButton(isSubmitting ? "Submitting..." : "Submit Inventory") {
                        showSubmitConfirmation = true
                    }
                    .disabled(isSubmitting)
                    .opacity(isSubmitting ? 0.5 : 1.0)

                    Button {
                        PeezyHaptics.light()
                        finishLater()
                    } label: {
                        Text("Finish later")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.6))
                            .underline()
                    }
                    .buttonStyle(.plain)
                    .disabled(isSubmitting)
                    .padding(.bottom, 8)
                }
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Room Name Sheet

    private var roomNameSheet: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                VStack(spacing: 16) {
                    Text("What room are you scanning?")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(PeezyTheme.Colors.deepInk)
                        .multilineTextAlignment(.center)

                    TextField("e.g. Living Room", text: $newRoomName)
                        .font(.system(size: 16, weight: .medium))
                        .multilineTextAlignment(.center)
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.primary.opacity(0.04))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
                        )
                        .padding(.horizontal, 24)
                }

                PeezyAssessmentButton("Begin Scanning") {
                    let name = newRoomName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    showRoomNameEntry = false
                    newRoomName = ""
                    sessionManager.startNewRoom(name: name)
                }
                .disabled(newRoomName.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(newRoomName.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1.0)
                .padding(.horizontal, 24)

                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showRoomNameEntry = false
                        newRoomName = ""
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Actions

    private func submitInventory() {
        isSubmitting = true
        Task {
            do {
                try await sessionManager.submitFinal()
                await MainActor.run {
                    isSubmitting = false
                    onSubmitted()
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    sessionManager.error = error.localizedDescription
                }
            }
        }
    }

    private func finishLater() {
        isSubmitting = true
        Task {
            do {
                try await sessionManager.saveDraft()
                await MainActor.run {
                    isSubmitting = false
                    onDismiss()
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    sessionManager.error = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Room Hub — Empty") {
    InventoryRoomHubView(
        sessionManager: InventorySessionManager(),
        onDismiss: { }
    )
}

#Preview("Room Hub — With Rooms") {
    let manager = InventorySessionManager()
    let _ = {
        manager.state = .roomList
        manager.scannedRooms = [
            ScannedRoom(id: "1", name: "Living Room", items: Array(repeating: InventoryItem(id: UUID().uuidString, name: "Sofa", category: "furniture", tier: "furniture", quantity: 1, sizeEstimate: "large", cubicFeet: 40, isFragile: false, isHighValue: false, confidence: 0.95, frameIndex: nil, boundingBox: nil, roomName: "Living Room", shouldMove: true, notes: ""), count: 12), scannedAt: Date()),
            ScannedRoom(id: "2", name: "Bedroom", items: Array(repeating: InventoryItem(id: UUID().uuidString, name: "Bed", category: "furniture", tier: "furniture", quantity: 1, sizeEstimate: "oversized", cubicFeet: 50, isFragile: false, isHighValue: false, confidence: 0.9, frameIndex: nil, boundingBox: nil, roomName: "Bedroom", shouldMove: true, notes: ""), count: 8), scannedAt: Date()),
        ]
    }()
    return InventoryRoomHubView(
        sessionManager: manager,
        onDismiss: { }
    )
}
#endif
