import SwiftUI

struct MoversEducationView: View {
    let headerTitle: String
    let title: String
    let message: String
    let callout: String
    let systemImage: String
    let accessibilityPrefix: String
    let showBack: Bool
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            TaskFlowHeader(
                taskTitle: headerTitle,
                showBack: showBack,
                onBack: onBack
            )

            Spacer(minLength: PeezyTheme.Layout.verticalSpacing)

            VStack(alignment: .leading, spacing: PeezyTheme.Layout.itemSpacing) {
                Image(systemName: systemImage)
                    .font(.largeTitle)
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .accessibilityHidden(true)

                Text(title)
                    .font(.title)
                    .bold()
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("\(accessibilityPrefix).title")

                Text(message)
                    .font(.body)
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("\(accessibilityPrefix).message")

                Text(callout)
                    .font(.headline)
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(PeezyTheme.Layout.cardPaddingSmall)
                    .background(
                        PeezyTheme.Colors.backgroundSecondary,
                        in: .rect(cornerRadius: PeezyTheme.Layout.cornerRadiusSmall)
                    )
                    .accessibilityIdentifier("\(accessibilityPrefix).callout")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .taskContentCard()
            .padding(.horizontal, PeezyTheme.Layout.horizontalPadding)
            .accessibilityIdentifier("\(accessibilityPrefix).card")

            Spacer(minLength: PeezyTheme.Layout.verticalSpacing)

            PeezyAssessmentButton("Continue", action: onContinue)
                .accessibilityIdentifier("\(accessibilityPrefix).continue")
                .padding(.horizontal, PeezyTheme.Layout.horizontalPadding)
                .padding(.bottom, PeezyTheme.Layout.verticalSpacing)
        }
        .accessibilityIdentifier("\(accessibilityPrefix).screen")
    }
}
