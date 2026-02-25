import SwiftUI

struct MoveConcerns: View {
    @State private var selectedConcerns: Set<String> = []
    @State private var otherText: String = ""
    @EnvironmentObject var assessmentData: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator
    
    // Animation states
    @State private var showContent = false
    
    let concerns = [
        ("Knowing what to do and when", "list.bullet.clipboard"),
        ("Finding time to actually pack", "shippingbox.fill"),
        ("Dealing with moving companies", "person.2.fill"),
        ("The fear of forgetting something important", "calendar"),
        ("Something else", "ellipsis")
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Equal spacing region
            VStack(spacing: 0) {
                Spacer(minLength: 0)

                // Multi-select tiles
                VStack(spacing: 12) {
                    ForEach(concerns, id: \.0) { concern in
                        VStack(spacing: 8) {
                            MultiSelectTile(
                                title: concern.0,
                                icon: concern.1,
                                isSelected: selectedConcerns.contains(concern.0),
                                onTap: {
                                    if selectedConcerns.contains(concern.0) {
                                        selectedConcerns.remove(concern.0)
                                        if concern.0 == "Something else" {
                                            otherText = ""
                                        }
                                    } else {
                                        selectedConcerns.insert(concern.0)
                                    }
                                }
                            )
                            .opacity(showContent ? 1 : 0)
                            .offset(y: showContent ? 0 : 30)
                            .animation(.easeOut(duration: 0.5).delay(0.5 + Double(concerns.firstIndex(where: { $0.0 == concern.0 }) ?? 0) * 0.1), value: showContent)

                            // Show text field when "Something else" is selected
                            if concern.0 == "Something else" && selectedConcerns.contains("Something else") {
                                TextField("Please specify...", text: $otherText)
                                    .font(.system(size: 16))
                                    .foregroundColor(PeezyTheme.Colors.deepInk)
                                    .padding(16)
                                    .background(Color.white)
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.gray.opacity(0.25), lineWidth: 1)
                                    )
                                    .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
                                    .transition(.opacity.combined(with: .scale))
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)

                // Gap 3: Options → Bottom
                Spacer(minLength: 0)
            }

            // Continue / Skip button
            PeezyAssessmentButton(selectedConcerns.isEmpty ? "None — Skip" : "Continue") {
                var concernsToSave = Array(selectedConcerns)
                
                if selectedConcerns.contains("Something else") && !otherText.isEmpty {
                    concernsToSave.removeAll { $0 == "Something else" }
                    concernsToSave.append("Something else: \(otherText)")
                }
                
                assessmentData.moveConcerns = concernsToSave
                coordinator.goToNext()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
            .opacity(showContent ? 1 : 0)
            .offset(y: showContent ? 0 : 30)
            .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.4), value: showContent)
        }
        .onAppear {
            selectedConcerns = Set(assessmentData.moveConcerns.map { concern in
                if concern.hasPrefix("Something else: ") {
                    otherText = String(concern.dropFirst("Something else: ".count))
                    return "Something else"
                }
                return concern
            })
            withAnimation {
                showContent = true
            }
        }
    }
}

#Preview {
    let manager = AssessmentDataManager()
    MoveConcerns()
        .environmentObject(manager)
        .environmentObject(AssessmentCoordinator(dataManager: manager))
}
