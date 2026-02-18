import SwiftUI

struct FinancialDetails: View {
    @State private var details: [String: String] = [:]
    @EnvironmentObject var assessmentData: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator

    @FocusState private var focusedCategory: String?
    @State private var showContent = false

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                VStack(spacing: 0) {
                    Spacer(minLength: 0)

                    HStack {
                        Text("Which ones?")
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

                    Spacer(minLength: 0)

                    ScrollView {
                        VStack(spacing: 16) {
                            ForEach(assessmentData.financialInstitutions, id: \.self) { category in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(category)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.white.opacity(0.6))

                                    TextField("", text: binding(for: category), prompt: Text("e.g. Chase, Amex...").foregroundColor(.white.opacity(0.3)))
                                        .font(.system(size: 16))
                                        .foregroundColor(.white)
                                        .textInputAutocapitalization(.words)
                                        .focused($focusedCategory, equals: category)
                                        .padding(.vertical, 14)
                                        .padding(.horizontal, 16)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(Color.white.opacity(0.08))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .stroke(Color.white.opacity(focusedCategory == category ? 0.4 : 0.15), lineWidth: 1)
                                                )
                                        )
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 300)
                    .padding(.horizontal, 24)
                    .opacity(showContent ? 1 : 0)
                    .offset(y: showContent ? 0 : 30)
                    .animation(.easeOut(duration: 0.5).delay(0.5), value: showContent)

                    Spacer(minLength: 0)
                }
            }
            .onTapGesture { focusedCategory = nil }

            PeezyAssessmentButton("Continue") {
                assessmentData.financialDetails = details
                coordinator.goToNext()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
            .opacity(showContent ? 1 : 0)
            .offset(y: showContent ? 0 : 30)
            .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.4), value: showContent)
        }
        .background(InteractiveBackground())
        .onAppear {
            details = assessmentData.financialDetails
            if let first = assessmentData.financialInstitutions.first {
                focusedCategory = first
            }
            withAnimation { showContent = true }
        }
    }

    private func binding(for category: String) -> Binding<String> {
        Binding(
            get: { details[category] ?? "" },
            set: { details[category] = $0 }
        )
    }
}

#Preview {
    let manager = AssessmentDataManager()
    manager.financialInstitutions = ["Bank Account", "Credit Card"]
    return FinancialDetails()
        .environmentObject(manager)
        .environmentObject(AssessmentCoordinator(dataManager: manager))
}
