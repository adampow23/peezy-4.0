import SwiftUI
import Combine

struct UserName: View {
    @State private var name = ""
    @EnvironmentObject var assessmentData: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator
    
    var body: some View {
        floatingTextInput(
            question: "What's your first name?",
            placeholder: "",
            stepNumber: AssessmentStep.UserName.stepNumber,
            totalSteps: AssessmentStep.UserName.totalSteps,
            text: $name,
            keyboardType: .default,
            onContinue: {
                assessmentData.UserName = name
                assessmentData.saveData()
                coordinator.goToNext(from: .UserName)
            },
            onBack: {
                coordinator.goBack()
            }
        )
        .navigationBarBackButtonHidden(true)
        .onAppear {
            name = assessmentData.UserName
        }
    }
}

#Preview {
    let manager = AssessmentDataManager()
    NavigationStack {
        UserName()
            .environmentObject(manager)
            .environmentObject(AssessmentCoordinator(dataManager: manager))  // ✅ Fixed
    }
}
