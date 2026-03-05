import SwiftUI

struct UserName: View {
    @State private var name = ""
    @EnvironmentObject var assessmentData: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator
    
    @FocusState private var isTextFieldFocused: Bool
    @State private var showContent = false
    
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                Spacer(minLength: 0)

                TextField("", text: $name, prompt: Text("First name").foregroundColor(Color.gray.opacity(0.5)))
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(PeezyTheme.Colors.deepInk)
                    .tint(PeezyTheme.Colors.accentBlue)
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .textContentType(.givenName)
                    .focused($isTextFieldFocused)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(minHeight: 52)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(.regularMaterial)
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.black.opacity(0.06))
                        }
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(
                                isTextFieldFocused ? PeezyTheme.Colors.accentBlue.opacity(0.6) : Color.black.opacity(0.1),
                                lineWidth: isTextFieldFocused ? 2 : 1
                            )
                    )
                    .shadow(
                        color: isTextFieldFocused ? PeezyTheme.Colors.accentBlue.opacity(0.2) : Color.black.opacity(0.3),
                        radius: 10,
                        y: 5
                    )
                    .padding(.horizontal, 24)
                    .opacity(showContent ? 1 : 0)
                    .offset(y: showContent ? 0 : 30)
                    .animation(.easeOut(duration: 0.5).delay(0.3), value: showContent)

                Spacer(minLength: 0)
            }
            .onTapGesture { isTextFieldFocused = false }

            PeezyAssessmentButton("Continue") {
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                assessmentData.userName = trimmed
                coordinator.goToNext()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
            .opacity(showContent ? 1 : 0)
            .offset(y: showContent ? 0 : 30)
            .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.4), value: showContent)
        }
        .onAppear {
            name = assessmentData.userName
            isTextFieldFocused = true
            withAnimation { showContent = true }
        }
    }
}

#Preview {
    let manager = AssessmentDataManager()
    UserName()
        .environmentObject(manager)
        .environmentObject(AssessmentCoordinator(dataManager: manager))
}
