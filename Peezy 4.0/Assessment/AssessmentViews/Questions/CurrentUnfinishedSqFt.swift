import SwiftUI

struct CurrentUnfinishedSqFt: View {
    @State private var sqft = ""
    @EnvironmentObject var assessmentData: AssessmentDataManager
    @EnvironmentObject var coordinator: AssessmentCoordinator
    
    @FocusState private var isTextFieldFocused: Bool
    @State private var showContent = false
    
    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    
                    HStack {
                        Text("Unfinished space?")
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
                    
                    HStack(spacing: 12) {
                        TextField("", text: $sqft, prompt: Text("e.g. 500 (or 0)").foregroundColor(.white.opacity(0.3)))
                            .font(.title3)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .keyboardType(.numberPad)
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
                        
                        Text("sq ft")
                            .font(.title3)
                            .foregroundColor(.white.opacity(0.5))
                    }
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
            
            PeezyAssessmentButton("Continue") {
                let trimmed = sqft.trimmingCharacters(in: .whitespacesAndNewlines)
                // Allow empty/0 — not everyone has unfinished space
                assessmentData.currentUnfinishedSqFt = trimmed.isEmpty ? "0" : trimmed
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
            sqft = assessmentData.currentUnfinishedSqFt
            isTextFieldFocused = true
            withAnimation {
                showContent = true
            }
        }
    }
}

#Preview {
    let manager = AssessmentDataManager()
    CurrentUnfinishedSqFt()
        .environmentObject(manager)
        .environmentObject(AssessmentCoordinator(dataManager: manager))
}
