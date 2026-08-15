import SwiftUI

struct MoversEquipView: View {
    let headerTitle: String
    let page: MoversPreparationPage
    let inventoryRooms: [ScannedRoom]
    let hasSubmittedInventory: Bool
    let showBack: Bool
    let isCompleting: Bool
    let actionError: String?
    let onBack: () -> Void
    let onPrimary: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            TaskFlowHeader(taskTitle: headerTitle, showBack: showBack, onBack: onBack)

            Spacer(minLength: PeezyTheme.Layout.verticalSpacing)

            pageBody
                .fitOrScrollCard(idPrefix: page.accessibilityPrefix)

            Spacer(minLength: PeezyTheme.Layout.verticalSpacing)

            if let actionError {
                Text(actionError)
                    .font(.callout)
                    .foregroundStyle(PeezyTheme.Colors.emotionalRed)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, PeezyTheme.Layout.horizontalPadding)
                    .padding(.bottom, PeezyTheme.Layout.verticalSpacingSmall)
                    .accessibilityIdentifier("movers.equip.error")
            }

            // Chain edge (plan A1): spawn-then-complete runs behind the final
            // button; it stays disabled while in flight and re-enables on
            // failure so a retry re-sends the same idempotency token.
            PeezyAssessmentButton(
                primaryTitle,
                disabled: isCompleting,
                action: onPrimary
            )
            .accessibilityIdentifier("movers.equip.getQuotes")
            .padding(.horizontal, PeezyTheme.Layout.horizontalPadding)
            .padding(.bottom, PeezyTheme.Layout.verticalSpacing)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("movers.equip.screen")
    }

    @ViewBuilder
    private var pageBody: some View {
        switch page.kind {
        case .education:
            EmptyView()
                .accessibilityIdentifier(page.accessibilityPrefix)
        case .intro:
            introBody
        case .callSheetSection(let items):
            callSheetBody(items: items)
        }
    }

    private var introBody: some View {
        VStack(alignment: .leading, spacing: PeezyTheme.Layout.itemSpacing) {
            VStack(alignment: .leading, spacing: PeezyTheme.Layout.verticalSpacingSmall) {
                Text(page.title)
                    .font(.title)
                    .bold()
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("movers.equip.title")

                if let body = page.body {
                    Text(body)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("movers.equip.intro")
                }
            }

            VStack(alignment: .leading, spacing: PeezyTheme.Layout.verticalSpacing) {
                TaskContentSectionTitle(
                    title: "Share your inventory",
                    systemImage: "square.and.arrow.up"
                )

                if hasSubmittedInventory {
                    ShareLink(item: InventoryLockedView.shareText(for: inventoryRooms)) {
                        Label("Share your inventory", systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(
                                maxWidth: .infinity,
                                minHeight: PeezyTheme.Layout.buttonHeightSmall
                            )
                            .background(
                                PeezyTheme.Colors.deepInk,
                                in: .rect(cornerRadius: PeezyTheme.Layout.cornerRadiusMedium)
                            )
                    }
                    .accessibilityIdentifier("movers.equip.shareInventory")
                } else {
                    Text("Scan your home first and every company prices the same job")
                        .font(.body)
                        .foregroundStyle(PeezyTheme.Colors.deepInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("movers.equip.inventoryMissing")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .taskContentCard()
            .accessibilityIdentifier("movers.equip.inventoryCard")
        }
        .padding(.horizontal, PeezyTheme.Layout.horizontalPadding)
    }

    private func callSheetBody(items: [String]) -> some View {
        VStack(alignment: .leading, spacing: PeezyTheme.Layout.itemSpacing) {
            Label(page.title, systemImage: page.systemImage)
                .font(.title)
                .bold()
                .foregroundStyle(PeezyTheme.Colors.deepInk)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("movers.equip.title")

            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: PeezyTheme.Layout.verticalSpacing) {
                    Circle()
                        .fill(PeezyTheme.Colors.deepInk.opacity(0.4))
                        .frame(width: 7, height: 7)
                        .padding(.top, 7)
                        .accessibilityHidden(true)

                    Text(item)
                        .font(.body)
                        .foregroundStyle(PeezyTheme.Colors.deepInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .taskContentCard()
        .padding(.horizontal, PeezyTheme.Layout.horizontalPadding)
        .accessibilityIdentifier(page.accessibilityPrefix)
    }

    private var primaryTitle: String {
        switch page.primary {
        case .advance:
            "Continue"
        case .getQuotes:
            isCompleting ? "Saving…" : "I'm getting quotes"
        }
    }
}
