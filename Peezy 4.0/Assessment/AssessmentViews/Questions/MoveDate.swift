import SwiftUI

struct MoveDate: View {
    @State private var selectedDate = Date()
    @State private var showError = false
    @State private var showContent = false
    @EnvironmentObject var assessmentData: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                Spacer(minLength: 0)

                PeezyCalendarPicker(
                    selectedDate: $selectedDate,
                    minimumDate: Date(),
                    accentColor: PeezyTheme.Colors.brandYellow
                )
                .padding(.horizontal, 20)
                .opacity(showContent ? 1 : 0)
                .offset(y: showContent ? 0 : 30)
                .animation(.easeOut(duration: 0.5).delay(0.3), value: showContent)

                Spacer(minLength: 0)
            }

            // Continue button
            PeezyAssessmentButton("Continue") {
                if selectedDate > Date() {
                    assessmentData.moveDate = selectedDate
                    coordinator.goToNext()
                } else {
                    showError = true
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
            .opacity(showContent ? 1 : 0)
            .offset(y: showContent ? 0 : 30)
            .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.4), value: showContent)
            .alert("Please choose a date in the future", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            }
        }
        .onAppear {
            selectedDate = assessmentData.moveDate
            withAnimation {
                showContent = true
            }
        }
    }
}

#Preview {
    let manager = AssessmentDataManager()
    MoveDate()
        .environmentObject(manager)
        .environmentObject(AssessmentCoordinator(dataManager: manager))
}
