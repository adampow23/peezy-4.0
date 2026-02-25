import SwiftUI

struct AssessmentContentArea<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            // Gap 1: Top → Options
            Spacer(minLength: 0)

            // Options content (provided by each view)
            content()

            // Gap 2: Options → Bottom
            Spacer(minLength: 0)
        }
    }
}
