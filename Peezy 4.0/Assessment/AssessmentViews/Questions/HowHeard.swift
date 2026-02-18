import SwiftUI

struct HowHeard: View {
    @State private var selected = ""
    @State private var referralCode = ""
    @EnvironmentObject var assessmentData: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator

    @State private var showContent = false
    private let lightHaptic = UIImpactFeedbackGenerator(style: .light)

    let options = ["Social Media", "Friend/Family", "Realtor", "Search Engine", "Referral", "Other"]
    let iconMap: [String: String] = [
        "Social Media": "iphone",
        "Friend/Family": "person.2.fill",
        "Realtor": "house.fill",
        "Search Engine": "magnifyingglass",
        "Referral": "envelope.open.fill",
        "Other": "ellipsis.circle.fill"
    ]

    var body: some View {
        VStack(spacing: 0) {
            AssessmentContentArea(questionText: "How'd you find us?", showContent: showContent) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                    ForEach(Array(options.enumerated()), id: \.element) { index, option in
                        SelectionTile(title: option, icon: iconMap[option], isSelected: selected == option, onTap: {
                            selected = option
                            assessmentData.howHeard = option

                            // Clear referral code when switching away from Referral
                            if option != "Referral" {
                                referralCode = ""
                                assessmentData.referralCode = ""
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    lightHaptic.impactOccurred()
                                    coordinator.goToNext()
                                }
                            }
                        })
                        .opacity(showContent ? 1 : 0)
                        .offset(y: showContent ? 0 : 30)
                        .animation(.easeOut(duration: 0.5).delay(0.5 + Double(index) * 0.1), value: showContent)
                    }
                }
                .padding(.horizontal, 20)

                // Conditional referral code text field
                if selected == "Referral" {
                    TextField("Referral code (optional)", text: $referralCode)
                        .font(.system(size: 16))
                        .foregroundColor(.black)
                        .padding()
                        .background(Color.white)
                        .cornerRadius(12)
                        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .transition(.opacity.combined(with: .scale))
                        .onChange(of: referralCode) { _, newValue in
                            assessmentData.referralCode = newValue
                        }
                }
            }

            // Continue button when Referral is selected
            if selected == "Referral" {
                PeezyAssessmentButton("Continue") {
                    lightHaptic.impactOccurred()
                    coordinator.goToNext()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
                .opacity(showContent ? 1 : 0)
                .offset(y: showContent ? 0 : 30)
                .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.4), value: showContent)
            }
        }
        .background(InteractiveBackground())
        .onAppear {
            selected = assessmentData.howHeard
            referralCode = assessmentData.referralCode
            withAnimation { showContent = true }
        }
    }
}

#Preview {
    let manager = AssessmentDataManager()
    HowHeard()
        .environmentObject(manager)
        .environmentObject(AssessmentCoordinator(dataManager: manager))
}
