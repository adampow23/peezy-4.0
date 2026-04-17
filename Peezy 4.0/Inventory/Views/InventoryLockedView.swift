//
//  InventoryLockedView.swift
//  Peezy 4.0
//

import SwiftUI

struct InventoryLockedView: View {
    let rooms: [ScannedRoom]
    let onDismiss: () -> Void

    var totalItems: Int {
        rooms.reduce(0) { $0 + $1.items.count }
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

                    Text("Need to make a change? Send us a message in the chat and we'll update it for you.")
                        .font(.system(size: 14))
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.top, 4)
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
                                    }
                                }
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
    }
}

#if DEBUG
#Preview("Inventory Locked") {
    InventoryLockedView(
        rooms: [
            ScannedRoom(
                id: "1",
                name: "Living Room",
                items: [
                    InventoryItem(id: "1", name: "Sofa", category: "furniture", tier: "furniture", quantity: 1, sizeEstimate: "large", cubicFeet: 40, isFragile: false, isHighValue: false, confidence: 1, frameIndex: nil, boundingBox: nil, roomName: "Living Room", shouldMove: true, notes: ""),
                    InventoryItem(id: "2", name: "Floor Lamp", category: "decor", tier: "furniture", quantity: 2, sizeEstimate: "medium", cubicFeet: 3, isFragile: true, isHighValue: false, confidence: 1, frameIndex: nil, boundingBox: nil, roomName: "Living Room", shouldMove: true, notes: "")
                ],
                scannedAt: Date()
            )
        ],
        onDismiss: {}
    )
}
#endif
