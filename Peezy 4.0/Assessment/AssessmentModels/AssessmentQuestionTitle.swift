import SwiftUI

struct AssessmentQuestionTitle: View {
    let text: String
    var widthFraction: CGFloat = 0.6
    var horizontalPadding: CGFloat = 20
    var animationDelay: Double = 0.3
    var isVisible: Bool = true
    
    var body: some View {
        GeometryReader { geo in
            HStack {
                Text(text)
                    .font(.system(size: 34, weight: .bold))
                    .frame(maxWidth: geo.size.width * widthFraction, alignment: .leading)
                    .multilineTextAlignment(.leading)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, horizontalPadding)
                Spacer()
            }
            .opacity(isVisible ? 1 : 0)
            .offset(x: isVisible ? 0 : -20)
            .animation(.easeOut(duration: 0.5).delay(animationDelay), value: isVisible)
        }
    }
}
