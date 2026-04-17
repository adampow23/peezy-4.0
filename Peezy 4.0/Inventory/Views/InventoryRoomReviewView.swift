//
//  InventoryRoomReviewView.swift
//  Peezy 4.0
//
//  Full item list for a scanned room. User can edit quantities,
//  delete items, add manual items, re-scan, or save.
//  Uses existing InventoryReviewViewModel for all data logic.
//

import SwiftUI

struct InventoryRoomReviewView: View {
    @State private var viewModel: InventoryReviewViewModel
    var onConfirm: ([InventoryItem]) -> Void
    var onRescan: (() -> Void)?

    // Add item sheet
    @State private var newItemName = ""
    @State private var newItemTier = "furniture"
    @State private var newItemCategory = "furniture"
    @State private var newItemSize = "medium"

    // Animation
    @State private var itemsAppeared = false
    @State private var confirmPressed = false
    @State private var boxableExpanded = false
    @State private var itemToDelete: InventoryItem?
    @State private var showDeleteConfirmation = false
    @State private var toastMessage: String?
    @State private var showToast = false

    private let categories = ["furniture", "electronics", "boxes", "appliance", "decor", "other"]
    private let sizes = ["small", "medium", "large", "oversized"]

    init(
        items: [InventoryItem],
        roomName: String,
        onConfirm: @escaping ([InventoryItem]) -> Void,
        onRescan: (() -> Void)? = nil
    ) {
        self._viewModel = State(initialValue: InventoryReviewViewModel(items: items, roomName: roomName))
        self.onConfirm = onConfirm
        self.onRescan = onRescan
    }

    var body: some View {
        ZStack {
            InteractiveBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                headerSection

                // Item list
                ScrollView {
                    VStack(spacing: 12) {
                        if !viewModel.furnitureItems.isEmpty {
                            furnitureSection
                        }
                        if !viewModel.boxableItems.isEmpty {
                            boxableSection
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 120)
                }

                // Sticky bottom
                bottomBar
            }
        }
        .sheet(isPresented: $viewModel.showAddItem) {
            addItemSheet
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                itemsAppeared = true
            }
        }
        .alert("Are you sure you're not moving this?", isPresented: $showDeleteConfirmation, presenting: itemToDelete) { item in
            Button("Cancel", role: .cancel) {
                itemToDelete = nil
            }
            Button("Remove", role: .destructive) {
                deleteItem(item)
                showToastMessage("\(item.name) removed")
                itemToDelete = nil
            }
        } message: { item in
            Text("\(item.name) will be removed from your inventory.")
        }
        .overlay(alignment: .bottom) {
            if showToast, let message = toastMessage {
                Text(message)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        Capsule().fill(PeezyTheme.Colors.deepInk)
                    )
                    .padding(.bottom, 40)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("\(viewModel.totalItemCount)")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(PeezyTheme.Colors.deepInk)

                Text(viewModel.totalItemCount == 1 ? " item in " : " items in ")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.4))

                Text(viewModel.roomName)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    // MARK: - Furniture Section

    private var furnitureSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section header
            HStack {
                Image(systemName: "sofa.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.35))
                Text("Furniture & Large Items")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.35))
                Spacer()
                Text("\(viewModel.furnitureItems.count)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.25))
            }
            .padding(.horizontal, 4)

            ForEach(Array(viewModel.furnitureItems.enumerated()), id: \.element.id) { index, item in
                itemRow(item)
                    .opacity(itemsAppeared ? 1 : 0)
                    .offset(y: itemsAppeared ? 0 : 20)
                    .animation(
                        .spring(response: 0.4, dampingFraction: 0.85).delay(Double(index) * 0.04),
                        value: itemsAppeared
                    )
            }
        }
    }

    // MARK: - Boxable Section

    private var boxableSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.35))
                Text("Boxable Items")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.35))
                Spacer()
                Text("\(viewModel.boxableItems.count)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.25))
            }
            .padding(.horizontal, 4)

            // Summary card
            VStack(alignment: .leading, spacing: 12) {
                // Chips
                FlowLayout(spacing: 6) {
                    ForEach(viewModel.boxableItems, id: \.id) { item in
                        boxableChip(item)
                    }
                }

                // Expand toggle
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        boxableExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(boxableExpanded ? "Hide details" : "See all items")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.5))
                        Image(systemName: boxableExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.5))
                    }
                }

                if boxableExpanded {
                    VStack(spacing: 6) {
                        ForEach(viewModel.boxableItems, id: \.id) { item in
                            HStack {
                                Text(item.name)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                                Spacer()
                                if item.quantity > 1 {
                                    Text("×\(item.quantity)")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.35))
                                }
                                removeItemButton(for: item)
                            }
                        }
                    }
                    .padding(.top, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
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
    }

    // MARK: - Item Row

    private func itemRow(_ item: InventoryItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                // Category icon
                Image(systemName: iconForCategory(item.category))
                    .font(.system(size: 18))
                    .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.4))
                    .frame(width: 28, height: 28)

                // Name + badges
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(PeezyTheme.Colors.deepInk)

                    HStack(spacing: 6) {
                        // Size badge
                        Text(item.sizeEstimate.capitalized)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.4))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.05))
                            .clipShape(Capsule())

                        // Fragile badge
                        if item.isFragile {
                            Text("Fragile")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color(uiColor: .systemOrange))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color(uiColor: .systemOrange).opacity(0.12))
                                .clipShape(Capsule())
                        }

                        // High value badge
                        if item.isHighValue {
                            Text("Value")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color(uiColor: .systemPurple))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color(uiColor: .systemPurple).opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                }

                Spacer()

                Text("×\(item.quantity)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.5))
                    .frame(minWidth: 28, alignment: .trailing)
                    .accessibilityLabel("Quantity \(item.quantity)")

                removeItemButton(for: item)
            }
        }
        .padding(14)
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
        .contextMenu {
            Button(role: .destructive) {
                confirmDelete(item)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func removeItemButton(for item: InventoryItem) -> some View {
        Button {
            confirmDelete(item)
        } label: {
            Image(systemName: "minus.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.3))
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove \(item.name)")
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 8) {
            // Add + Save
            HStack(spacing: 10) {
                // Add item
                Button {
                    PeezyHaptics.light()
                    viewModel.showAddItem = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .bold))
                        Text("Add")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.6))
                    .padding(.horizontal, 16)
                    .frame(height: 48)
                    .background(.regularMaterial)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )
                }

                // Save room
                Button {
                    PeezyHaptics.light()
                    confirmPressed = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        confirmPressed = false
                        onConfirm(viewModel.items)
                    }
                } label: {
                    Text(viewModel.confirmButtonText)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(height: 48)
                        .frame(maxWidth: .infinity)
                        .background(PeezyTheme.Colors.deepInk)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
                .scaleEffect(confirmPressed ? 0.97 : 1.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: confirmPressed)
            }

            // Re-scan
            if let onRescan {
                Button(action: {
                    PeezyHaptics.light()
                    onRescan()
                }) {
                    Text("Re-scan this room")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.4))
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    // MARK: - Chips

    private func boxableChip(_ item: InventoryItem) -> some View {
        HStack(spacing: 3) {
            Text(item.name)
                .font(.system(size: 12, weight: .medium))
            if item.quantity > 1 {
                Text("×\(item.quantity)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.35))
            }
        }
        .foregroundStyle(item.shouldMove ? PeezyTheme.Colors.deepInk.opacity(0.6) : PeezyTheme.Colors.deepInk.opacity(0.25))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.primary.opacity(item.shouldMove ? 0.06 : 0.03))
        .clipShape(Capsule())
        .strikethrough(!item.shouldMove)
    }

    // MARK: - Add Item Sheet

    private var addItemSheet: some View {
        NavigationStack {
            Form {
                Section("Item name") {
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
                            Label(cat.capitalized, systemImage: iconForCategory(cat))
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

    private func confirmDelete(_ item: InventoryItem) {
        PeezyHaptics.light()
        itemToDelete = item
        showDeleteConfirmation = true
    }

    private func deleteItem(_ item: InventoryItem) {
        guard let index = viewModel.items.firstIndex(where: { $0.id == item.id }) else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            viewModel.deleteItem(at: IndexSet(integer: index))
        }
    }

    private func showToastMessage(_ message: String) {
        toastMessage = message
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            showToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeOut(duration: 0.3)) {
                showToast = false
            }
        }
    }

    private func iconForCategory(_ category: String) -> String {
        switch category {
        case "furniture": return "sofa.fill"
        case "electronics": return "tv.fill"
        case "boxes": return "shippingbox.fill"
        case "appliance": return "refrigerator.fill"
        case "decor": return "lamp.desk.fill"
        default: return "questionmark.circle"
        }
    }
}

// MARK: - Flow Layout (for boxable chips)

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
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

// MARK: - Previews

#if DEBUG
#Preview("Room Review") {
    InventoryRoomReviewView(
        items: [
            InventoryItem(id: "1", name: "Sectional Sofa", category: "furniture", tier: "furniture", quantity: 1, sizeEstimate: "oversized", cubicFeet: 45, isFragile: false, isHighValue: false, confidence: 0.95, frameIndex: nil, boundingBox: nil, roomName: "Living Room", shouldMove: true, notes: ""),
            InventoryItem(id: "2", name: "65\" TV", category: "electronics", tier: "furniture", quantity: 1, sizeEstimate: "large", cubicFeet: 8, isFragile: true, isHighValue: true, confidence: 0.92, frameIndex: nil, boundingBox: nil, roomName: "Living Room", shouldMove: true, notes: ""),
            InventoryItem(id: "3", name: "Floor Lamp", category: "decor", tier: "furniture", quantity: 2, sizeEstimate: "medium", cubicFeet: 3, isFragile: true, isHighValue: false, confidence: 0.88, frameIndex: nil, boundingBox: nil, roomName: "Living Room", shouldMove: true, notes: ""),
            InventoryItem(id: "4", name: "Bookshelf", category: "furniture", tier: "furniture", quantity: 1, sizeEstimate: "large", cubicFeet: 18, isFragile: false, isHighValue: false, confidence: 0.97, frameIndex: nil, boundingBox: nil, roomName: "Living Room", shouldMove: true, notes: ""),
            InventoryItem(id: "5", name: "Books", category: "boxes", tier: "boxable", quantity: 50, sizeEstimate: "small", cubicFeet: 1, isFragile: false, isHighValue: false, confidence: 0.9, frameIndex: nil, boundingBox: nil, roomName: "Living Room", shouldMove: true, notes: ""),
            InventoryItem(id: "6", name: "Decorative Items", category: "decor", tier: "boxable", quantity: 12, sizeEstimate: "small", cubicFeet: 0.5, isFragile: true, isHighValue: false, confidence: 0.85, frameIndex: nil, boundingBox: nil, roomName: "Living Room", shouldMove: true, notes: ""),
        ],
        roomName: "Living Room",
        onConfirm: { items in print("Saved \(items.count) items") },
        onRescan: { print("Re-scan") }
    )
}
#endif
