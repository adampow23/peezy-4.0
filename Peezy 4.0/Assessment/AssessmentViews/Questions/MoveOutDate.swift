import SwiftUI

struct MoveOutDate: View {
    @State private var selectedDate = Date()
    @State private var showError = false
    @State private var showContent = false
    @EnvironmentObject var assessmentData: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator
    
    var body: some View {
        VStack(spacing: 0) {
            // Equal spacing region
            GeometryReader { geo in
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    
                    // Question
                    HStack {
                        Text("Move-out date?")
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
                    
                    Spacer(minLength: 0)
                }
            }
            
            // Continue button
            PeezyAssessmentButton("Continue") {
                if selectedDate > Date() {
                    assessmentData.moveOutDate = selectedDate
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
        .background(InteractiveBackground())
        .onAppear {
            selectedDate = assessmentData.moveOutDate
            withAnimation {
                showContent = true
            }
        }
    }
}

#Preview {
    let manager = AssessmentDataManager()
    MoveOutDate()
        .environmentObject(manager)
        .environmentObject(AssessmentCoordinator(dataManager: manager))
}//
//  MoveOutDate.swift
//  Peezy 4.0
//
//  Created by Adam Powell on 2/10/26.
//

