import SwiftUI

struct PetSelection: View {
    @State private var selectedPets: Set<String> = []
    @EnvironmentObject var assessmentData: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator
    
    @State private var showContent = false
    
    let petTypes = [
        ("Dog", "dog.fill"),
        ("Cat", "cat.fill"),
        ("Bird", "bird.fill"),
        ("Fish", "fish.fill"),
        ("Other", "pawprint.fill")
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Which pets?")
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
                    
                    Spacer(minLength: 0)
                    
                    VStack(spacing: 12) {
                        ForEach(Array(petTypes.enumerated()), id: \.element.0) { index, pet in
                            MultiSelectTile(
                                title: pet.0,
                                icon: pet.1,
                                isSelected: selectedPets.contains(pet.0),
                                onTap: {
                                    if selectedPets.contains(pet.0) {
                                        selectedPets.remove(pet.0)
                                    } else {
                                        selectedPets.insert(pet.0)
                                    }
                                }
                            )
                            .opacity(showContent ? 1 : 0)
                            .offset(y: showContent ? 0 : 30)
                            .animation(.easeOut(duration: 0.5).delay(0.5 + Double(index) * 0.1), value: showContent)
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    Spacer(minLength: 0)
                }
            }
            
            PeezyAssessmentButton("Continue") {
                assessmentData.petSelection = Array(selectedPets)
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
            selectedPets = Set(assessmentData.petSelection)
            withAnimation { showContent = true }
        }
    }
}

#Preview {
    let manager = AssessmentDataManager()
    PetSelection()
        .environmentObject(manager)
        .environmentObject(AssessmentCoordinator(dataManager: manager))
}//
//  PetSelection.swift
//  Peezy 4.0
//
//  Created by Adam Powell on 2/10/26.
//

