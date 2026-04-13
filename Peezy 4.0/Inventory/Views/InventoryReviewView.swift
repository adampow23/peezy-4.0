import SwiftUI

struct InventoryReviewView: View {
    @State private var viewModel: InventoryReviewViewModel
    var onConfirm: ([InventoryItem]) -> Void
    var onRescan: (() -> Void)? = nil

    // Add item sheet fields
    @State private var newItemName = ""
    @State private var newItemCategory = "furniture"
    @State private var newItemSize = "medium"
    @State private var newItemTier = "furniture"

    // Animation state
    @State private var showConfetti = false
    @State private var itemsAppeared = false
    @State private var confirmPressed = false

    // Boxable section expand/collapse
    @State private var boxableExpanded = false

    private let categories = ["furniture", "electronics", "boxes", "appliance", "decor", "other"]
    private let sizes = ["small", "medium", "large", "oversized"]

    init(items: [InventoryItem], roomName: String, onConfirm: @escaping ([InventoryItem]) -> Void, onRescan: (() -> Void)? = nil) {
        self._viewModel = State(initialValue: InventoryReviewViewModel(items: items, roomName: roomName))
        self.onConfirm = onConfirm
        self.onRescan = onRescan
    }

    var body: some View {
        ZStack {
            InteractiveBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                headerSection

                ScrollView {
                    VStack(spacing: PeezyTheme.Layout.verticalSpacing) {
                        // MARK: - Furniture Section
                        if !viewModel.furnitureItems.isEmpty {
                            furnitureSection
                        }

                        // MARK: - Boxable Section
                        if !viewModel.boxableItems.isEmpty {
                            boxableSection
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

    // MARK: - Furniture Section

    private var furnitureSection: some View {
        VStack(alignment: .leading, spacing: PeezyTheme.Layout.verticalSpacingSmall) {
            // Section header
            HStack {
                Image(systemName: "sofa.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(PeezyTheme.Colors.textSecondary)
                Text("Furniture & Large Items")
                    .font(PeezyTheme.Typography.calloutMedium)
                    .foregroundStyle(PeezyTheme.Colors.textSecondary)
                Spacer()
                Text("\(viewModel.furnitureItems.count)")
                    .font(PeezyTheme.Typography.calloutMedium)
                    .foregroundStyle(PeezyTheme.Colors.textTertiary)
            }
            .padding(.horizontal, 4)

            ForEach(Array(viewModel.furnitureItems.enumerated()), id: \.element.id) { index, item in
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
    }

    // MARK: - Boxable Section

    private var boxableSection: some View {
        VStack(alignment: .leading, spacing: PeezyTheme.Layout.verticalSpacingSmall) {
            // Section header
            HStack {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(PeezyTheme.Colors.textSecondary)
                Text("Packing Estimate")
                    .font(PeezyTheme.Typography.calloutMedium)
                    .foregroundStyle(PeezyTheme.Colors.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 4)

            // Summary card
            VStack(alignment: .leading, spacing: PeezyTheme.Layout.verticalSpacing) {
                // Box estimate headline
                HStack(alignment: .firstTextBaseline) {
                    Text(viewModel.boxEstimateDescription)
                        .font(PeezyTheme.Typography.title2)
                        .foregroundStyle(PeezyTheme.Colors.textPrimary)
                    Spacer()
                }

                Text("Every household packs differently — this is a ballpark based on what we found in this room.")
                    .font(PeezyTheme.Typography.caption)
                    .foregroundStyle(PeezyTheme.Colors.textTertiary)

                // Item summary chips
                FlowLayout(spacing: 6) {
                    ForEach(viewModel.boxableItems, id: \.id) { item in
                        boxableChip(item)
                    }
                }

                // Expandable detail list
                Button {
                    withAnimation(PeezyTheme.Animation.spring) {
                        boxableExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(boxableExpanded ? "Hide details" : "See all items")
                            .font(PeezyTheme.Typography.callout)
                            .foregroundStyle(PeezyTheme.Colors.infoBlue)
                        Image(systemName: boxableExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(PeezyTheme.Colors.infoBlue)
                    }
                }

                if boxableExpanded {
                    VStack(spacing: 8) {
                        ForEach(viewModel.boxableItems, id: \.id) { item in
                            HStack {
                                Text(item.name)
                                    .font(PeezyTheme.Typography.callout)
                                    .foregroundStyle(PeezyTheme.Colors.textPrimary)
                                Spacer()
                                if item.quantity > 1 {
                                    Text("×\(item.quantity)")
                                        .font(PeezyTheme.Typography.callout)
                                        .foregroundStyle(PeezyTheme.Colors.textTertiary)
                                }
                                Toggle("", isOn: Binding(
                                    get: { item.shouldMove },
                                    set: { _ in viewModel.toggleShouldMove(for: item) }
                                ))
                                .labelsHidden()
                                .tint(PeezyTheme.Colors.infoBlue)
                            }
                            if item.id != viewModel.boxableItems.last?.id {
                                Divider()
                                    .overlay(Color.white.opacity(0.1))
                            }
                        }
                    }
                    .padding(.top, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
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
            .opacity(itemsAppeared ? 1 : 0)
            .offset(y: itemsAppeared ? 0 : 20)
            .animation(
                PeezyTheme.Animation.spring.delay(Double(viewModel.furnitureItems.count) * 0.05 + 0.1),
                value: itemsAppeared
            )
        }
    }

    private func boxableChip(_ item: InventoryItem) -> some View {
        HStack(spacing: 4) {
            Text(item.name)
                .font(PeezyTheme.Typography.caption)
            if item.quantity > 1 {
                Text("×\(item.quantity)")
                    .font(PeezyTheme.Typography.caption)
                    .foregroundStyle(PeezyTheme.Colors.textTertiary)
            }
        }
        .foregroundStyle(item.shouldMove ? PeezyTheme.Colors.textSecondary : PeezyTheme.Colors.textTertiary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(PeezyTheme.Colors.backgroundTertiary.opacity(item.shouldMove ? 1 : 0.5))
        .clipShape(Capsule())
        .strikethrough(!item.shouldMove)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: PeezyTheme.Layout.itemSpacing) {
                // Add Item button
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

                // Confirm button
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

            // Re-scan button
            if let onRescan {
                Button(action: {
                    PeezyHaptics.light()
                    onRescan()
                }) {
                    Text("Re-scan this room")
                        .font(PeezyTheme.Typography.callout)
                        .foregroundStyle(PeezyTheme.Colors.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
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
                Section("What kind of item?") {
                    Picker("Tier", selection: $newItemTier) {
                        Text("Furniture / Large Item").tag("furniture")
                        Text("Packable / Goes in a Box").tag("boxable")
                    }
                    .pickerStyle(.segmented)
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
                        viewModel.addManualItem(name: newItemName, category: newItemCategory, size: newItemSize, tier: newItemTier)
                        newItemName = ""
                        newItemCategory = "furniture"
                        newItemSize = "medium"
                        newItemTier = "furniture"
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

// MARK: - Flow Layout (for boxable chips)

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: ProposedViewSize(width: bounds.width, height: nil), subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
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
