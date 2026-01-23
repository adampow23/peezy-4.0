import SwiftUI

struct AssessmentContentArea<Content: View>: View {
    let questionText: String
    let showContent: Bool
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                // Gap 1: Progress → Question
                Spacer(minLength: 0)
                
                // Question (wraps at 60% of available width, multi-line)
                HStack {
                    Text(questionText)
                        .font(.system(size: 34, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: geo.size.width * 0.6, alignment: .leading)
                        .multilineTextAlignment(.leading)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 20)
                    Spacer(minLength: 0)
                }
                .opacity(showContent ? 1 : 0)
                .offset(x: showContent ? 0 : -20)
                .animation(.easeOut(duration: 0.5).delay(0.3), value: showContent)
                
                // Gap 2: Question → Options
                Spacer(minLength: 0)
                
                // Options content (provided by each view)
                content()
                
                // Gap 3: Options → Bottom
                Spacer(minLength: 0)
            }
        }
    }
}
