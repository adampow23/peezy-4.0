import SwiftUI

struct MoversEquipView: View {
    let headerTitle: String
    let callSheet: TaskCallSheet?
    let inventoryRooms: [ScannedRoom]
    let hasSubmittedInventory: Bool
    let isCompleting: Bool
    let actionError: String?
    let onBack: () -> Void
    let onGetQuotes: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            TaskFlowHeader(taskTitle: headerTitle, showBack: true, onBack: onBack)

            ScrollView {
                VStack(alignment: .leading, spacing: PeezyTheme.Layout.itemSpacing) {
                    VStack(alignment: .leading, spacing: PeezyTheme.Layout.verticalSpacingSmall) {
                        Text("Get three quotes")
                            .font(.title)
                            .bold()
                            .foregroundStyle(PeezyTheme.Colors.deepInk)
                            .accessibilityIdentifier("movers.equip.title")

                        Text("Give every company the same facts, then get the rate and time estimate in writing.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("movers.equip.intro")
                    }

                    if let callSheet {
                        CallSheetSection(callSheet: callSheet)
                    }

                    VStack(alignment: .leading, spacing: PeezyTheme.Layout.verticalSpacing) {
                        TaskContentSectionTitle(
                            title: "Share your inventory",
                            systemImage: "square.and.arrow.up"
                        )

                        if hasSubmittedInventory {
                            ShareLink(item: InventoryLockedView.shareText(for: inventoryRooms)) {
                                Label("Share your inventory", systemImage: "square.and.arrow.up")
                                    .font(PeezyTheme.Typography.headline)
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
                .padding(.vertical, PeezyTheme.Layout.verticalSpacing)
            }
            .scrollIndicators(.hidden)

            if let actionError {
                Text(actionError)
                    .font(.callout)
                    .foregroundStyle(PeezyTheme.Colors.emotionalRed)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, PeezyTheme.Layout.horizontalPadding)
                    .padding(.bottom, PeezyTheme.Layout.verticalSpacingSmall)
                    .accessibilityIdentifier("movers.equip.error")
            }

            // Chain edge (plan A1): spawn-then-complete runs behind this button;
            // it stays disabled while in flight and re-enables on failure so a
            // retry re-sends the same idempotency token.
            PeezyAssessmentButton(
                isCompleting ? "Saving…" : "I'm getting quotes",
                disabled: isCompleting,
                action: onGetQuotes
            )
            .accessibilityIdentifier("movers.equip.getQuotes")
            .padding(.horizontal, PeezyTheme.Layout.horizontalPadding)
            .padding(.bottom, PeezyTheme.Layout.verticalSpacing)
        }
        .accessibilityIdentifier("movers.equip.screen")
    }
}
