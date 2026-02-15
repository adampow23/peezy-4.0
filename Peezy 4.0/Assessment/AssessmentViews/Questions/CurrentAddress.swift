import SwiftUI

struct CurrentAddress: View {
    @State private var address = ""
    @EnvironmentObject var assessmentData: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator
    
    @FocusState private var isTextFieldFocused: Bool
    
    // Animation states
    @State private var showContent = false
    
    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    
                    HStack {
                        Text("Current address?")
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
                    
                    // Address text field
                    TextField("", text: $address, prompt: Text("Street, City, State, ZIP").foregroundColor(.white.opacity(0.3)))
                        .font(.title3)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .textContentType(.fullStreetAddress)
                        .focused($isTextFieldFocused)
                        .padding(.vertical, 16)
                        .padding(.horizontal, 24)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white.opacity(0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.white.opacity(isTextFieldFocused ? 0.4 : 0.15), lineWidth: 1)
                                )
                        )
                        .padding(.horizontal, 24)
                        .opacity(showContent ? 1 : 0)
                        .offset(y: showContent ? 0 : 30)
                        .animation(.easeOut(duration: 0.5).delay(0.5), value: showContent)
                    
                    Spacer(minLength: 0)
                }
            }
            .onTapGesture {
                isTextFieldFocused = false
            }
            
            // Continue button
            PeezyAssessmentButton("Continue") {
                let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                assessmentData.currentAddress = trimmed
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
            address = assessmentData.currentAddress
            isTextFieldFocused = true
            withAnimation {
                showContent = true
            }
        }
    }
}

#Preview {
    let manager = AssessmentDataManager()
    CurrentAddress()
        .environmentObject(manager)
        .environmentObject(AssessmentCoordinator(dataManager: manager))
}//
//  CurrentAddress.swift
//  Peezy 4.0
//
//  Created by Adam Powell on 2/10/26.
//

