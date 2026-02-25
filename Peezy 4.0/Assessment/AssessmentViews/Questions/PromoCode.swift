import SwiftUI

struct PromoCode: View {
    @State private var code = ""
    @EnvironmentObject var assessmentData: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator

    @FocusState private var isTextFieldFocused: Bool
    @State private var showContent = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                Spacer(minLength: 0)

                TextField("", text: $code, prompt: Text("Promo code").foregroundColor(Color.gray.opacity(0.5)))
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(PeezyTheme.Colors.deepInk)
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .focused($isTextFieldFocused)
                    .padding(16)
                    .background(Color.white)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gray.opacity(0.25), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
                    .padding(.horizontal, 24)
                    .opacity(showContent ? 1 : 0)
                    .offset(y: showContent ? 0 : 30)
                    .animation(.easeOut(duration: 0.5).delay(0.3), value: showContent)

                Spacer(minLength: 0)
            }
            .onTapGesture { isTextFieldFocused = false }

            PeezyAssessmentButton(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No code — Skip" : "Apply") {
                let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
                assessmentData.promoCode = trimmed
                coordinator.goToNext()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
            .opacity(showContent ? 1 : 0)
            .offset(y: showContent ? 0 : 30)
            .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.4), value: showContent)
        }
        .onAppear {
            code = assessmentData.promoCode
            isTextFieldFocused = true
            withAnimation { showContent = true }
        }
    }
}

#Preview {
    let manager = AssessmentDataManager()
    PromoCode()
        .environmentObject(manager)
        .environmentObject(AssessmentCoordinator(dataManager: manager))
}
