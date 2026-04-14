//
//  InventoryItemConfirmView.swift
//  Peezy 4.0
//
//  One-by-one review of low-confidence furniture items.
//  Shows cropped photo from the scan frame + "Is this a [name]?" question.
//  User confirms ("That's right") or corrects ("Not quite" → text field).
//  Uses HStack buttons matching the edit-mode pattern from ConfirmAddressCard.
//

import SwiftUI

// MARK: - View

struct InventoryItemConfirmView: View {
    @State private var viewModel: ItemConfirmViewModel
    var onComplete: ([InventoryItem]) -> Void

    init(
        items: [InventoryItem],
        sessionId: String,
        userId: String,
        onComplete: @escaping ([InventoryItem]) -> Void
    ) {
        self._viewModel = State(initialValue: ItemConfirmViewModel(
            items: items,
            sessionId: sessionId,
            userId: userId
        ))
        self.onComplete = onComplete
    }

    var body: some View {
        ZStack {
            InteractiveBackground()
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                // Progress
                progressHeader

                // Item card
                if let item = viewModel.currentItem {
                    confirmationCard(for: item)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                        .id(item.id)
                }

                Spacer()
            }
            .padding(.horizontal, 24)
        }
        .task {
            await viewModel.loadCurrentFrame()
        }
    }

    // MARK: - Progress

    private var progressHeader: some View {
        VStack(spacing: 8) {
            Text("\(viewModel.currentIndex + 1) of \(viewModel.itemsToConfirm.count)")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.5))

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 4)

                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(PeezyTheme.Colors.brandYellow)
                        .frame(width: geo.size.width * viewModel.progress, height: 4)
                        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: viewModel.progress)
                }
            }
            .frame(height: 4)
            .padding(.horizontal, 40)

            Text("Help us identify a few items")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.35))
        }
    }

    // MARK: - Confirmation Card

    private func confirmationCard(for item: InventoryItem) -> some View {
        VStack(spacing: 20) {
            // Photo
            itemImage

            // Question or edit field
            if viewModel.isEditing {
                VStack(spacing: 12) {
                    TextField("What is this item?", text: $viewModel.correctedName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(PeezyTheme.Colors.deepInk)
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.primary.opacity(0.04))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                        )
                        .submitLabel(.done)
                        .onSubmit { confirmCorrected() }
                }
            } else {
                Text("Is this a **\(item.name)**?")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .multilineTextAlignment(.center)
            }

            // Action buttons — HStack (edit-mode pattern)
            HStack(spacing: 12) {
                // Left: Not quite / Cancel
                Button {
                    PeezyHaptics.light()
                    withAnimation(.spring(duration: 0.4, bounce: 0.15)) {
                        if viewModel.isEditing {
                            viewModel.isEditing = false
                            viewModel.correctedName = ""
                        } else {
                            viewModel.isEditing = true
                            viewModel.correctedName = ""
                        }
                    }
                } label: {
                    Text(viewModel.isEditing ? "Cancel" : "Not quite")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.6))
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.primary.opacity(0.05))
                        )
                }
                .buttonStyle(.plain)

                // Right: That's right / Save correction
                Button {
                    PeezyHaptics.light()
                    if viewModel.isEditing {
                        confirmCorrected()
                    } else {
                        confirmAsIs()
                    }
                } label: {
                    Text(viewModel.isEditing ? "Save correction" : "That's right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(PeezyTheme.Colors.deepInk)
                        )
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isEditing && viewModel.correctedName.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(viewModel.isEditing && viewModel.correctedName.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1.0)
            }
        }
        .padding(24)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.regularMaterial)
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white.opacity(0.15))
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
            }
        )
    }

    // MARK: - Item Image

    @ViewBuilder
    private var itemImage: some View {
        if viewModel.isLoadingFrame {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.04))
                .frame(height: 200)
                .overlay { ProgressView().tint(PeezyTheme.Colors.deepInk.opacity(0.3)) }
        } else if let image = viewModel.croppedImage {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.04))
                .frame(height: 200)
                .overlay {
                    VStack(spacing: 8) {
                        Image(systemName: "photo")
                            .font(.system(size: 32))
                            .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.2))
                        Text("Image unavailable")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.3))
                    }
                }
        }
    }

    // MARK: - Actions

    private func confirmAsIs() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            viewModel.confirmCurrent(correctedName: nil)
        }
        advanceOrComplete()
    }

    private func confirmCorrected() {
        let name = viewModel.correctedName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            viewModel.confirmCurrent(correctedName: name)
        }
        advanceOrComplete()
    }

    private func advanceOrComplete() {
        if viewModel.isComplete {
            onComplete(viewModel.allItems)
        } else {
            Task { await viewModel.loadCurrentFrame() }
        }
    }
}

// MARK: - View Model

@Observable
final class ItemConfirmViewModel {
    private(set) var allItems: [InventoryItem]
    let itemsToConfirm: [InventoryItem]
    private(set) var currentIndex: Int = 0
    var isEditing = false
    var correctedName = ""
    var croppedImage: UIImage?
    var isLoadingFrame = false

    private let sessionId: String
    private let userId: String
    private let storageService = InventoryStorageService()
    private let confirmationIndices: [Int]

    init(items: [InventoryItem], sessionId: String, userId: String) {
        self.allItems = items
        self.sessionId = sessionId
        self.userId = userId

        var indices: [Int] = []
        var toConfirm: [InventoryItem] = []
        for (index, item) in items.enumerated() {
            if item.tier == "furniture" && item.confidence < InventorySessionManager.confidenceThreshold {
                indices.append(index)
                toConfirm.append(item)
            }
        }
        self.confirmationIndices = indices
        self.itemsToConfirm = toConfirm
    }

    var currentItem: InventoryItem? {
        guard currentIndex < itemsToConfirm.count else { return nil }
        return itemsToConfirm[currentIndex]
    }

    var progress: Double {
        guard !itemsToConfirm.isEmpty else { return 1.0 }
        return Double(currentIndex) / Double(itemsToConfirm.count)
    }

    var isComplete: Bool {
        currentIndex >= itemsToConfirm.count
    }

    func confirmCurrent(correctedName: String?) {
        guard currentIndex < confirmationIndices.count else { return }
        let itemIndex = confirmationIndices[currentIndex]

        if let correctedName {
            allItems[itemIndex].name = correctedName
        }
        allItems[itemIndex].confidence = 1.0

        isEditing = false
        self.correctedName = ""
        croppedImage = nil
        currentIndex += 1
    }

    func loadCurrentFrame() async {
        guard let item = currentItem,
              let frameIndex = item.frameIndex else {
            croppedImage = nil
            return
        }

        isLoadingFrame = true
        defer { isLoadingFrame = false }

        do {
            let frameData = try await storageService.downloadFrame(
                userId: userId,
                sessionId: sessionId,
                frameIndex: frameIndex
            )

            guard let fullImage = UIImage(data: frameData) else {
                croppedImage = nil
                return
            }

            if let bb = item.boundingBox {
                croppedImage = cropImage(fullImage, to: bb)
            } else {
                croppedImage = fullImage
            }
        } catch {
            croppedImage = nil
        }
    }

    private func cropImage(_ image: UIImage, to box: BoundingBox) -> UIImage {
        let w = image.size.width
        let h = image.size.height
        let pad: Double = 0.1
        let px = max(0, box.x - pad * box.width)
        let py = max(0, box.y - pad * box.height)
        let pw = min(1.0 - px, box.width * (1 + 2 * pad))
        let ph = min(1.0 - py, box.height * (1 + 2 * pad))
        let rect = CGRect(x: px * w, y: py * h, width: pw * w, height: ph * h)
        guard rect.width > 0, rect.height > 0,
              let cg = image.cgImage,
              let cropped = cg.cropping(to: rect) else { return image }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Item Confirm") {
    InventoryItemConfirmView(
        items: [
            InventoryItem(id: "1", name: "Dining Table", category: "furniture", tier: "furniture", quantity: 1, sizeEstimate: "large", cubicFeet: 20, isFragile: false, isHighValue: false, confidence: 0.6, frameIndex: 0, boundingBox: nil, roomName: "Kitchen", shouldMove: true, notes: ""),
            InventoryItem(id: "2", name: "Bookshelf", category: "furniture", tier: "furniture", quantity: 1, sizeEstimate: "large", cubicFeet: 15, isFragile: false, isHighValue: false, confidence: 0.5, frameIndex: 1, boundingBox: nil, roomName: "Living Room", shouldMove: true, notes: ""),
            InventoryItem(id: "3", name: "Sofa", category: "furniture", tier: "furniture", quantity: 1, sizeEstimate: "oversized", cubicFeet: 40, isFragile: false, isHighValue: false, confidence: 0.95, frameIndex: 2, boundingBox: nil, roomName: "Living Room", shouldMove: true, notes: ""),
        ],
        sessionId: "preview-session",
        userId: "preview-user",
        onComplete: { items in print("Confirmed \(items.count) items") }
    )
}
#endif
