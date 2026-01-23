import SwiftUI

struct MoveConcerns: View {
    @State private var selectedConcerns: Set<String> = []
    @State private var otherText: String = ""
    @EnvironmentObject var assessmentData: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator
    
    // Animation states
    @State private var showContent = false
    
    let concerns = [
        ("Building my to-do list", "list.bullet.clipboard"),
        ("Packing/preparing for move day", "shippingbox.fill"),
        ("Hiring pros (movers, cleaners, etc.)", "person.2.fill"),
        ("Planning/staying on track", "calendar"),
        ("Other", "ellipsis")
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Animated Progress Header
            AssessmentProgressHeader(
                currentStep: AssessmentStep.MoveConcerns.stepNumber,
                totalSteps: AssessmentStep.MoveConcerns.totalSteps,
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
                    
                    // Question with subtitle
                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("What worries you most about moving?")
                                .font(.system(size: 34, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: geo.size.width * 0.6, alignment: .leading)
                                .multilineTextAlignment(.leading)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)

                            Text("Tap all that apply")
                                .font(.system(size: 16))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        .padding(.horizontal, 20)
                        Spacer(minLength: 0)
                    }
                    .opacity(showContent ? 1 : 0)
                    .offset(x: showContent ? 0 : -20)
                    .animation(.easeOut(duration: 0.5).delay(0.3), value: showContent)
                    
                    // Gap 2: Question → Options
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
                                            if concern.0 == "Other" {
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
                                
                                // Show text field when "Other" is selected
                                if concern.0 == "Other" && selectedConcerns.contains("Other") {
                                    TextField("Please specify...", text: $otherText)
                                        .font(.system(size: 16))
                                        .foregroundColor(.black)
                                        .padding()
                                        .background(Color.white)
                                        .cornerRadius(12)
                                        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
                                        .transition(.opacity.combined(with: .scale))
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    // Gap 3: Options → Bottom
                    Spacer(minLength: 0)
                }
            }
            
            // Continue button
            PeezyAssessmentButton("Continue") {
                var concernsToSave = Array(selectedConcerns)
                
                if selectedConcerns.contains("Other") && !otherText.isEmpty {
                    concernsToSave.removeAll { $0 == "Other" }
                    concernsToSave.append("Other: \(otherText)")
                }
                
                assessmentData.MoveConcerns = concernsToSave
                assessmentData.saveData()
                coordinator.goToNext(from: .MoveConcerns)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
            .opacity(showContent ? 1 : 0)
            .offset(y: showContent ? 0 : 30)
            .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.4), value: showContent)
        }
        .navigationBarBackButtonHidden(true)
        .background(InteractiveBackground())
        .onAppear {
            selectedConcerns = Set(assessmentData.MoveConcerns.map { concern in
                if concern.hasPrefix("Other: ") {
                    otherText = String(concern.dropFirst(7))
                    return "Other"
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
    NavigationStack {
        MoveConcerns()
            .environmentObject(manager)
            .environmentObject(AssessmentCoordinator(dataManager: manager))
    }
}
