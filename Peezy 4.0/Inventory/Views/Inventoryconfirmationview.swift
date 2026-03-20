import SwiftUI

struct InventoryConfirmationView: View {
    @State private var viewModel: InventoryConfirmationViewModel
    var onComplete: ([InventoryItem]) -> Void

    init(
        items: [InventoryItem],
        sessionId: String,
        userId: String,
        onComplete: @escaping ([InventoryItem]) -> Void
    ) {
        self._viewModel = State(initialValue: InventoryConfirmationViewModel(
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

            VStack(spacing: PeezyTheme.Layout.sectionSpacing) {
                Spacer()

                // Progress indicator
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
            .padding(.horizontal, PeezyTheme.Layout.horizontalPadding)
        }
        .task {
            await viewModel.loadCurrentFrame()
        }
    }

    // MARK: - Progress Header

    private var progressHeader: some View {
        VStack(spacing: PeezyTheme.Layout.verticalSpacingSmall) {
            Text("\(viewModel.currentIndex + 1) of \(viewModel.itemsToConfirm.count)")
                .font(PeezyTheme.Typography.calloutMedium)
                .foregroundStyle(PeezyTheme.Colors.textSecondary)

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(PeezyTheme.Colors.backgroundTertiary)
                        .frame(height: 4)

                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(PeezyTheme.Colors.brandYellow)
                        .frame(width: geo.size.width * viewModel.progress, height: 4)
                        .animation(PeezyTheme.Animation.spring, value: viewModel.progress)
                }
            }
            .frame(height: 4)
            .padding(.horizontal, 40)

            Text("Help us identify a few items")
                .font(PeezyTheme.Typography.callout)
                .foregroundStyle(PeezyTheme.Colors.textTertiary)
        }
    }

    // MARK: - Confirmation Card

    private func confirmationCard(for item: InventoryItem) -> some View {
        VStack(spacing: PeezyTheme.Layout.verticalSpacing) {
            // Cropped image or placeholder
            itemImage

            // Question
            Text("Is this a **\(item.name)**?")
                .font(PeezyTheme.Typography.title2)
                .foregroundStyle(PeezyTheme.Colors.textPrimary)
                .multilineTextAlignment(.center)

            // Correction text field
            if viewModel.isEditing {
                TextField("What is this item?", text: $viewModel.correctedName)
                    .font(PeezyTheme.Typography.body)
                    .textFieldStyle(.plain)
                    .padding(PeezyTheme.Layout.cardPaddingSmall)
                    .background(PeezyTheme.Colors.backgroundTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadiusSmall, style: .continuous))
                    .onSubmit {
                        confirmCorrected()
                    }
            }

            // Action buttons
            HStack(spacing: PeezyTheme.Layout.verticalSpacing) {
                // "No" / Edit button
                Button {
                    withAnimation(PeezyTheme.Animation.spring) {
                        if viewModel.isEditing {
                            // Cancel editing
                            viewModel.isEditing = false
                            viewModel.correctedName = ""
                        } else {
                            viewModel.isEditing = true
                            viewModel.correctedName = ""
                        }
                    }
                } label: {
                    Text(viewModel.isEditing ? "Cancel" : "No, it's not")
                        .font(PeezyTheme.Typography.calloutMedium)
                        .foregroundStyle(PeezyTheme.Colors.textPrimary)
                        .frame(height: PeezyTheme.Layout.buttonHeight)
                        .frame(maxWidth: .infinity)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadiusPill, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadiusPill, style: .continuous)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                }

                // "Yes" / Submit correction button
                Button {
                    if viewModel.isEditing {
                        confirmCorrected()
                    } else {
                        confirmAsIs()
                    }
                } label: {
                    Text(viewModel.isEditing ? "Save" : "Yes, correct")
                        .font(PeezyTheme.Typography.headline)
                        .foregroundStyle(PeezyTheme.Colors.deepInk)
                        .frame(height: PeezyTheme.Layout.buttonHeight)
                        .frame(maxWidth: .infinity)
                        .background(PeezyTheme.Gradients.brandYellow)
                        .clipShape(RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadiusPill, style: .continuous))
                        .shadow(color: PeezyTheme.Shadows.buttonShadowColor, radius: PeezyTheme.Shadows.buttonShadowRadius, x: 0, y: PeezyTheme.Shadows.buttonShadowY)
                }
                .disabled(viewModel.isEditing && viewModel.correctedName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(PeezyTheme.Layout.cardPadding)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadius, style: .continuous)
                    .fill(.regularMaterial)
                RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.15))
                RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            }
        )
        .shadow(color: PeezyTheme.Shadows.subtleShadowColor, radius: PeezyTheme.Shadows.subtleShadowRadius, x: 0, y: PeezyTheme.Shadows.subtleShadowY)
    }

    // MARK: - Item Image

    @ViewBuilder
    private var itemImage: some View {
        if viewModel.isLoadingFrame {
            RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadiusSmall, style: .continuous)
                .fill(PeezyTheme.Colors.backgroundTertiary)
                .frame(height: 200)
                .overlay {
                    ProgressView()
                        .tint(PeezyTheme.Colors.textTertiary)
                }
        } else if let image = viewModel.croppedImage {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 200)
                .clipShape(RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadiusSmall, style: .continuous))
        } else {
            // Fallback — no image available
            RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadiusSmall, style: .continuous)
                .fill(PeezyTheme.Colors.backgroundTertiary)
                .frame(height: 200)
                .overlay {
                    VStack(spacing: 8) {
                        Image(systemName: "photo")
                            .font(.system(size: 32))
                            .foregroundStyle(PeezyTheme.Colors.textTertiary)
                        Text("Image unavailable")
                            .font(PeezyTheme.Typography.caption)
                            .foregroundStyle(PeezyTheme.Colors.textTertiary)
                    }
                }
        }
    }

    // MARK: - Actions

    private func confirmAsIs() {
        withAnimation(PeezyTheme.Animation.spring) {
            viewModel.confirmCurrent(correctedName: nil)
        }
        advanceOrComplete()
    }

    private func confirmCorrected() {
        let name = viewModel.correctedName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        withAnimation(PeezyTheme.Animation.spring) {
            viewModel.confirmCurrent(correctedName: name)
        }
        advanceOrComplete()
    }

    private func advanceOrComplete() {
        if viewModel.isComplete {
            onComplete(viewModel.allItems)
        } else {
            Task {
                await viewModel.loadCurrentFrame()
            }
        }
    }
}

// MARK: - View Model

@Observable
final class InventoryConfirmationViewModel {
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

    /// Indices into allItems for the items that need confirmation
    private let confirmationIndices: [Int]

    init(items: [InventoryItem], sessionId: String, userId: String) {
        self.allItems = items
        self.sessionId = sessionId
        self.userId = userId

        // Find furniture-tier items below confidence threshold
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
        // Mark as user-confirmed by setting confidence to 1.0
        allItems[itemIndex].confidence = 1.0

        // Reset state and advance
        isEditing = false
        correctedName.map { _ in self.correctedName = "" }
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

            // Crop to bounding box if available
            if let bb = item.boundingBox {
                croppedImage = cropImage(fullImage, to: bb)
            } else {
                croppedImage = fullImage
            }
        } catch {
            #if DEBUG
            print("[InventoryConfirmation] Failed to load frame \(frameIndex): \(error.localizedDescription)")
            #endif
            croppedImage = nil
        }
    }

    /// Crop a UIImage using normalized bounding box coordinates (0.0-1.0)
    private func cropImage(_ image: UIImage, to box: BoundingBox) -> UIImage {
        let imageWidth = image.size.width
        let imageHeight = image.size.height

        // Add 10% padding around the bounding box for context
        let padding: Double = 0.1
        let paddedX = max(0, box.x - padding * box.width)
        let paddedY = max(0, box.y - padding * box.height)
        let paddedWidth = min(1.0 - paddedX, box.width * (1 + 2 * padding))
        let paddedHeight = min(1.0 - paddedY, box.height * (1 + 2 * padding))

        let cropRect = CGRect(
            x: paddedX * imageWidth,
            y: paddedY * imageHeight,
            width: paddedWidth * imageWidth,
            height: paddedHeight * imageHeight
        )

        // Ensure crop rect is valid
        guard cropRect.width > 0, cropRect.height > 0 else { return image }

        guard let cgImage = image.cgImage,
              let croppedCG = cgImage.cropping(to: cropRect) else {
            return image
        }

        return UIImage(cgImage: croppedCG, scale: image.scale, orientation: image.imageOrientation)
    }
}//
//  Inventoryconfirmationview.swift
//  Peezy 4.0
//
//  Created by Adam Powell on 3/19/26.
//

