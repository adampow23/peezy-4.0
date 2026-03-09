import SwiftUI

struct InventoryReviewView: View {
    @State private var viewModel: InventoryReviewViewModel
    var onConfirm: ([InventoryItem]) -> Void

    // Add item sheet fields
    @State private var newItemName = ""
    @State private var newItemCategory = "furniture"
    @State private var newItemSize = "medium"

    // Animation state
    @State private var showConfetti = false
    @State private var itemsAppeared = false
    @State private var confirmPressed = false

    private let categories = ["furniture", "electronics", "boxes", "appliance", "decor", "other"]
    private let sizes = ["small", "medium", "large", "oversized"]

    init(items: [InventoryItem], roomName: String, onConfirm: @escaping ([InventoryItem]) -> Void) {
        self._viewModel = State(initialValue: InventoryReviewViewModel(items: items, roomName: roomName))
        self.onConfirm = onConfirm
    }

    var body: some View {
        ZStack {
            InteractiveBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                headerSection

                ScrollView {
                    LazyVStack(spacing: PeezyTheme.Layout.verticalSpacing) {
                        ForEach(Array(viewModel.items.enumerated()), id: \.element.id) { index, item in
                            InventoryItemRow(
                                item: item,
                                onToggleMove: { viewModel.toggleShouldMove(for: item) },
                                onUpdateQuantity: { newQty in viewModel.updateQuantity(for: item, newQuantity: newQty) },
                                onDelete: { deleteItem(item) }
                            )
                            .transition(.asymmetric(
                                insertion: .scale.combined(with: .opacity),
                                removal: .move(edge: .trailing).combined(with: .opacity)
                            ))
                            .opacity(itemsAppeared ? 1 : 0)
                            .offset(y: itemsAppeared ? 0 : 20)
                            .animation(
                                PeezyTheme.Animation.spring.delay(Double(index) * 0.05),
                                value: itemsAppeared
                            )
                        }
                    }
                    .padding(.horizontal, PeezyTheme.Layout.horizontalPadding)
                    .padding(.top, PeezyTheme.Layout.verticalSpacing)
                    .padding(.bottom, 100)
                }

                bottomBar
            }

            // Confetti overlay
            ConfettiView(isActive: $showConfetti, intensity: .low)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .sheet(isPresented: $viewModel.showAddItem) {
            addItemSheet
        }
        .onAppear {
            showConfetti = true
            withAnimation(PeezyTheme.Animation.spring) {
                itemsAppeared = true
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: PeezyTheme.Layout.verticalSpacingSmall) {
            Text("\(viewModel.totalItemCount)")
                .font(PeezyTheme.Typography.title2)
                .foregroundStyle(PeezyTheme.Colors.textPrimary)
            +
            Text(" item\(viewModel.totalItemCount == 1 ? "" : "s") in ")
                .font(PeezyTheme.Typography.callout)
                .foregroundStyle(PeezyTheme.Colors.textSecondary)
            +
            Text(viewModel.roomName)
                .font(PeezyTheme.Typography.title2)
                .foregroundStyle(PeezyTheme.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, PeezyTheme.Layout.cardPadding)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: PeezyTheme.Layout.itemSpacing) {
            // Add Item button — capsule with + icon
            Button {
                viewModel.showAddItem = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Add")
                        .font(PeezyTheme.Typography.calloutMedium)
                }
                .foregroundStyle(PeezyTheme.Colors.infoBlue)
                .padding(.horizontal, 16)
                .frame(height: PeezyTheme.Layout.buttonHeightSmall)
                .background(.regularMaterial)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(PeezyTheme.Colors.infoBlue.opacity(0.3), lineWidth: 1)
                )
            }

            // Confirm button — full width gradient
            Button {
                confirmPressed = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    confirmPressed = false
                    onConfirm(viewModel.items)
                }
            } label: {
                Text(viewModel.confirmButtonText)
                    .font(PeezyTheme.Typography.headline)
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .frame(height: PeezyTheme.Layout.buttonHeight)
                    .frame(maxWidth: .infinity)
                    .background(PeezyTheme.Gradients.brandYellow)
                    .clipShape(RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadiusPill, style: .continuous))
                    .shadow(color: PeezyTheme.Shadows.buttonShadowColor, radius: PeezyTheme.Shadows.buttonShadowRadius, x: 0, y: PeezyTheme.Shadows.buttonShadowY)
            }
            .scaleEffect(confirmPressed ? PeezyTheme.Animation.pressScale : 1.0)
            .animation(PeezyTheme.Animation.spring, value: confirmPressed)
        }
        .padding(.horizontal, PeezyTheme.Layout.horizontalPadding)
        .padding(.vertical, PeezyTheme.Layout.cardPaddingSmall)
    }

    // MARK: - Add Item Sheet

    private var addItemSheet: some View {
        NavigationStack {
            Form {
                Section("Item Name") {
                    TextField("e.g. Floor Lamp", text: $newItemName)
                }
                Section("Category") {
                    Picker("Category", selection: $newItemCategory) {
                        ForEach(categories, id: \.self) { cat in
                            Label(cat.capitalized, systemImage: iconName(for: cat))
                                .tag(cat)
                        }
                    }
                    .pickerStyle(.menu)
                }
                Section("Size") {
                    Picker("Size", selection: $newItemSize) {
                        ForEach(sizes, id: \.self) { size in
                            Text(size.capitalized).tag(size)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Add Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { viewModel.showAddItem = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard !newItemName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        viewModel.addManualItem(name: newItemName, category: newItemCategory, size: newItemSize)
                        newItemName = ""
                        newItemCategory = "furniture"
                        newItemSize = "medium"
                        viewModel.showAddItem = false
                    }
                    .disabled(newItemName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Helpers

    private func deleteItem(_ item: InventoryItem) {
        guard let index = viewModel.items.firstIndex(where: { $0.id == item.id }) else { return }
        withAnimation(PeezyTheme.Animation.spring) {
            viewModel.deleteItem(at: IndexSet(integer: index))
        }
    }
}

// MARK: - Item Row

private struct InventoryItemRow: View {
    let item: InventoryItem
    var onToggleMove: () -> Void
    var onUpdateQuantity: (Int) -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PeezyTheme.Layout.verticalSpacingSmall) {
            HStack(spacing: PeezyTheme.Layout.verticalSpacingSmall) {
                // Category icon
                Image(systemName: iconName(for: item.category))
                    .font(.system(size: 20))
                    .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.5))
                    .frame(width: 32, height: 32)

                // Name + badges
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(PeezyTheme.Typography.bodyMedium)
                        .foregroundStyle(PeezyTheme.Colors.textPrimary)

                    HStack(spacing: 6) {
                        sizeBadge
                        confidenceIndicator
                    }
                }

                Spacer()

                // Quantity stepper
                quantityStepper
            }

            HStack {
                Toggle("Moving this", isOn: Binding(
                    get: { item.shouldMove },
                    set: { _ in onToggleMove() }
                ))
                .font(PeezyTheme.Typography.callout)
                .foregroundStyle(PeezyTheme.Colors.textSecondary)
                .tint(PeezyTheme.Colors.infoBlue)
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
        .contextMenu {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var sizeBadge: some View {
        Text(item.sizeEstimate.capitalized)
            .font(PeezyTheme.Typography.caption)
            .foregroundStyle(PeezyTheme.Colors.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(PeezyTheme.Colors.backgroundTertiary)
            .clipShape(Capsule())
    }

    private var confidenceIndicator: some View {
        Circle()
            .fill(confidenceColor)
            .frame(width: 8, height: 8)
    }

    private var confidenceColor: Color {
        if item.confidence >= 0.8 {
            return PeezyTheme.Colors.successGreen
        } else if item.confidence >= 0.5 {
            return PeezyTheme.Colors.brandYellow
        } else {
            return PeezyTheme.Colors.warningOrange
        }
    }

    private var quantityStepper: some View {
        HStack(spacing: 0) {
            Button {
                onUpdateQuantity(item.quantity - 1)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(item.quantity > 1 ? PeezyTheme.Colors.textPrimary : PeezyTheme.Colors.textTertiary)
                    .frame(width: 32, height: 32)
                    .background(PeezyTheme.Colors.backgroundTertiary)
                    .clipShape(Circle())
            }
            .disabled(item.quantity <= 1)

            Text("\(item.quantity)")
                .font(PeezyTheme.Typography.bodyMedium)
                .foregroundStyle(PeezyTheme.Colors.textPrimary)
                .frame(minWidth: 28)

            Button {
                onUpdateQuantity(item.quantity + 1)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(PeezyTheme.Colors.textPrimary)
                    .frame(width: 32, height: 32)
                    .background(PeezyTheme.Colors.backgroundTertiary)
                    .clipShape(Circle())
            }
        }
    }
}

// MARK: - Icon Mapping

private func iconName(for category: String) -> String {
    switch category {
    case "furniture": return "sofa.fill"
    case "electronics": return "tv.fill"
    case "boxes": return "shippingbox.fill"
    case "appliance": return "refrigerator.fill"
    case "decor": return "lamp.desk.fill"
    default: return "questionmark.circle"
    }
}
