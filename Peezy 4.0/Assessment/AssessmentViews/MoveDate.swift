import SwiftUI

struct MoveDate: View {
    @State private var selectedDate = Date()
    @State private var showError = false
    @State private var showContent = false
    @EnvironmentObject var assessmentData: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator
    
    var body: some View {
        VStack(spacing: 0) {
            // Animated Progress Header
            AssessmentProgressHeader(
                currentStep: AssessmentStep.MoveDate.stepNumber,
                totalSteps: AssessmentStep.MoveDate.totalSteps,
                onBack: {
                    coordinator.goBack()
                },
                onCompletion: {
                    // Not used for intermediate steps
                }
            )
            
            // Equal spacing region below the progress line
            GeometryReader { geo in
                VStack(spacing: 0) {
                    // Gap 1: Progress → Question
                    Spacer(minLength: 0)
                    
                    // Question
                    HStack {
                        Text("When are you moving?")
                            .font(.system(size: 34, weight: .bold))
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
                    
                    // Gap 2: Question → Calendar
                    Spacer(minLength: 0)
                    
                    // Calendar picker
                    PeezyCalendarPicker(
                        selectedDate: $selectedDate,
                        minimumDate: Date(),
                        accentColor: PeezyTheme.Colors.brandYellow
                    )
                    .padding(.horizontal, 20)
                    .opacity(showContent ? 1 : 0)
                    .offset(y: showContent ? 0 : 30)
                    .animation(.easeOut(duration: 0.5).delay(0.5), value: showContent)
                    
                    // Gap 3: Calendar → Bottom
                    Spacer(minLength: 0)
                }
            }
            
            // Continue button
            PeezyAssessmentButton("Continue") {
                if selectedDate > Date() {
                    assessmentData.MoveDate = selectedDate
                    assessmentData.saveData()
                    coordinator.goToNext(from: .MoveDate)
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
        .navigationBarBackButtonHidden(true)
        .background(Color(.systemBackground))
        .onAppear {
            selectedDate = assessmentData.MoveDate
            withAnimation {
                showContent = true
            }
        }
    }
}

#Preview {
    let manager = AssessmentDataManager()
    NavigationStack {
        MoveDate()
            .environmentObject(manager)
            .environmentObject(AssessmentCoordinator(dataManager: manager))
    }
}
