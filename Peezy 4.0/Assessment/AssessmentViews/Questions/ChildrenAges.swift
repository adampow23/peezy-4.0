import SwiftUI

struct ChildrenAges: View {
    @State private var selectedAges: Set<String> = []
    @EnvironmentObject var assessmentData: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator
    
    @State private var showContent = false
    
    let ageRanges = [
        ("Under 5", "figure.and.child.holdinghands"),
        ("5-12", "figure.child"),
        ("13-17", "figure.stand"),
        ("18+", "person.fill")
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Age groups?")
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
                        ForEach(Array(ageRanges.enumerated()), id: \.element.0) { index, range in
                            MultiSelectTile(
                                title: range.0,
                                icon: range.1,
                                isSelected: selectedAges.contains(range.0),
                                onTap: {
                                    if selectedAges.contains(range.0) {
                                        selectedAges.remove(range.0)
                                    } else {
                                        selectedAges.insert(range.0)
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
                assessmentData.childrenAges = Array(selectedAges)
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
            selectedAges = Set(assessmentData.childrenAges)
            withAnimation { showContent = true }
        }
    }
}

#Preview {
    let manager = AssessmentDataManager()
    ChildrenAges()
        .environmentObject(manager)
        .environmentObject(AssessmentCoordinator(dataManager: manager))
}//
//  ChildrenAges.swift
//  Peezy 4.0
//
//  Created by Adam Powell on 2/10/26.
//

