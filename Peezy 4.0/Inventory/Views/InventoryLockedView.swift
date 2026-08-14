//
//  InventoryLockedView.swift
//  Peezy 4.0
//

import SwiftUI

struct InventoryLockedView: View {
    var sessionManager: InventorySessionManager
    let onDismiss: () -> Void

    @State private var roomForNewItem: ScannedRoom?
    @State private var itemToRemove: InventoryItem?
    @State private var showRemoveConfirmation = false
    @State private var persistenceError = ""
    @State private var showPersistenceError = false

    private var rooms: [ScannedRoom] {
        sessionManager.scannedRooms
    }

    private var totalItems: Int {
        rooms.reduce(0) { $0 + $1.items.count }
    }

    private var shareText: String {
        var sections = ["MOVING INVENTORY"]
        var grandTotal = 0

        for room in rooms {
            let subtotal = room.items.reduce(0) { $0 + $1.quantity }
            var lines = [room.name]
            lines.append(contentsOf: room.items.map { item in
                var line = "\(item.name) ×\(item.quantity)"
                if item.isFragile { line += " (fragile)" }
                if item.isHighValue { line += " (high value)" }
                return line
            })
            lines.append("Room subtotal: \(subtotal) item\(subtotal == 1 ? "" : "s")")
            sections.append(lines.joined(separator: "\n"))
            grandTotal += subtotal
        }

        sections.append("GRAND TOTAL: \(grandTotal) item\(grandTotal == 1 ? "" : "s")")
        return sections.joined(separator: "\n\n")
    }

    var body: some View {
        ZStack {
            InteractiveBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(PeezyTheme.Colors.deepInk)
                            .padding(12)
                            .background(Circle().fill(Color.white.opacity(0.7)))
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    ShareLink(item: shareText) {
                        Label("Share inventory", systemImage: "square.and.arrow.up")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(PeezyTheme.Colors.deepInk)
                            .padding(12)
                            .background(Circle().fill(Color.white.opacity(0.7)))
                            .labelStyle(.iconOnly)
                    }
                    .accessibilityLabel("Share inventory")
                    .accessibilityIdentifier("inventoryShareButton")

                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                VStack(spacing: 16) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(PeezyTheme.Colors.deepInk)

                    Text("Inventory submitted")
                        .font(.system(size: 28, weight: .heavy))
                        .foregroundStyle(PeezyTheme.Colors.deepInk)

                    Text("\(rooms.count) room\(rooms.count == 1 ? "" : "s") · \(totalItems) item\(totalItems == 1 ? "" : "s")")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.6))

                    Text("Your room-by-room list stays available here. Add or remove items anytime, and your packing plan will stay up to date.")
                        .font(.system(size: 14))
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.top, 4)
                        .accessibilityIdentifier("inventoryLocked.editingHelp")
                }
                .padding(.top, 40)

                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(rooms) { room in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(room.name)
                                        .font(.system(size: 18, weight: .bold))
                                        .foregroundStyle(PeezyTheme.Colors.deepInk)

                                    Spacer()

                                    Text("\(room.items.count) items")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.5))
                                }

                                ForEach(room.items) { item in
                                    HStack {
                                        Text("•")
                                            .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.4))

                                        Text(item.name)
                                            .font(.system(size: 14))
                                            .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.8))

                                        if item.quantity > 1 {
                                            Text("×\(item.quantity)")
                                                .font(.system(size: 13, weight: .medium))
                                                .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.5))
                                        }

                                        Spacer()

                                        Button {
                                            PeezyHaptics.light()
                                            itemToRemove = item
                                            showRemoveConfirmation = true
                                        } label: {
                                            Label("Remove \(item.name)", systemImage: "minus.circle.fill")
                                                .font(.system(size: 20))
                                                .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.35))
                                                .labelStyle(.iconOnly)
                                                .frame(width: 44, height: 44)
                                                .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("Remove \(item.name)")
                                        .accessibilityIdentifier("inventoryRemoveItemButton")
                                    }
                                }

                                Button {
                                    PeezyHaptics.light()
                                    roomForNewItem = room
                                } label: {
                                    Label("Add item", systemImage: "plus")
                                        .font(.system(size: 14, weight: .semibold))
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                }
                                .buttonStyle(.bordered)
                                .tint(PeezyTheme.Colors.deepInk)
                                .accessibilityIdentifier("inventoryAddItemButton")
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.white.opacity(0.6))
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 40)
                }

                Spacer()
            }
        }
        .sheet(item: $roomForNewItem) { room in
            InventoryAddItemSheet(roomName: room.name) { item in
                addItem(item, toRoomID: room.id)
            }
        }
        .alert("Remove item?", isPresented: $showRemoveConfirmation, presenting: itemToRemove) { item in
            Button("Cancel", role: .cancel) {
                itemToRemove = nil
            }
            .accessibilityIdentifier("inventoryRemoveItemCancelButton")

            Button("Remove", role: .destructive) {
                removeItem(item)
                itemToRemove = nil
            }
            .accessibilityIdentifier("inventoryRemoveItemConfirmButton")
        } message: { item in
            Text("\(item.name) will be removed from your submitted inventory.")
        }
        .alert("Couldn't update inventory", isPresented: $showPersistenceError) {
        } message: {
            Text(persistenceError)
        }
    }

    private func addItem(_ item: InventoryItem, toRoomID roomID: String) {
        guard let roomIndex = sessionManager.scannedRooms.firstIndex(where: { $0.id == roomID }) else { return }
        sessionManager.scannedRooms[roomIndex].items.append(item)
        persistChanges()
    }

    private func removeItem(_ item: InventoryItem) {
        sessionManager.removeItem(item)
        persistChanges()
    }

    private func persistChanges() {
        Task {
            do {
                try await sessionManager.persistRooms()
            } catch {
                persistenceError = error.localizedDescription
                showPersistenceError = true
            }
        }
    }
}

#if DEBUG
#Preview("Inventory Locked") {
    let manager = InventorySessionManager()
    let _ = {
        manager.submissionStatus = .submitted
        manager.scannedRooms = [
            ScannedRoom(
                id: "1",
                name: "Living Room",
                items: [
                    InventoryItem(id: "1", name: "Sofa", category: "furniture", tier: "furniture", quantity: 1, sizeEstimate: "large", cubicFeet: 40, isFragile: false, isHighValue: false, confidence: 1, frameIndex: nil, boundingBox: nil, roomName: "Living Room", shouldMove: true, notes: ""),
                    InventoryItem(id: "2", name: "Floor Lamp", category: "decor", tier: "furniture", quantity: 2, sizeEstimate: "medium", cubicFeet: 3, isFragile: true, isHighValue: false, confidence: 1, frameIndex: nil, boundingBox: nil, roomName: "Living Room", shouldMove: true, notes: "")
                ],
                scannedAt: Date()
            )
        ]
    }()
    return InventoryLockedView(
        sessionManager: manager,
        onDismiss: {}
    )
}
#endif
