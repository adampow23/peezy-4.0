import SwiftUI

struct HealthcareProviders: View {
    @State private var currentEntry = ""
    @State private var entries: [String] = []
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
                        Text("Healthcare providers?")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: geo.size.width * 0.6, alignment: .leading)
                            .multilineTextAlignment(.leading).lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 20)
                        Spacer(minLength: 0)
                    }
                    .opacity(showContent ? 1 : 0).offset(x: showContent ? 0 : -20)
                    .animation(.easeOut(duration: 0.5).delay(0.3), value: showContent)
                    Spacer(minLength: 0)
                    
                    if !entries.isEmpty {
                        ScrollView {
                            VStack(spacing: 8) {
                                ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                                    HStack {
                                        Text(entry).font(.system(size: 16)).foregroundColor(.white)
                                        Spacer()
                                        Button { entries.remove(at: index) } label: {
                                            Image(systemName: "xmark.circle.fill").foregroundColor(.white.opacity(0.4))
                                        }
                                    }
                                    .padding(.horizontal, 16).padding(.vertical, 12)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08)))
                                }
                            }
                        }
                        .frame(maxHeight: 200)
                        .padding(.horizontal, 24).padding(.bottom, 16)
                    }
                    
                    HStack(spacing: 12) {
                        TextField("", text: $currentEntry, prompt: Text("e.g. Dr. Smith, Aetna, Kaiser").foregroundColor(.white.opacity(0.3)))
                            .font(.system(size: 16)).foregroundColor(.white)
                            .textInputAutocapitalization(.words).focused($isTextFieldFocused)
                            .padding(.vertical, 14).padding(.horizontal, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(isTextFieldFocused ? 0.4 : 0.15), lineWidth: 1))
                            )
                            .onSubmit { addEntry() }
                        Button { addEntry() } label: {
                            Image(systemName: "plus.circle.fill").font(.system(size: 28))
                                .foregroundColor(currentEntry.trimmingCharacters(in: .whitespaces).isEmpty ? .white.opacity(0.2) : .blue)
                        }
                        .disabled(currentEntry.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(.horizontal, 24)
                    .opacity(showContent ? 1 : 0).offset(y: showContent ? 0 : 30)
                    .animation(.easeOut(duration: 0.5).delay(0.5), value: showContent)
                    Spacer(minLength: 0)
                }
            }
            .onTapGesture { isTextFieldFocused = false }
            
            PeezyAssessmentButton(entries.isEmpty ? "None — Skip" : "Continue") {
                assessmentData.healthcareProviders = entries
                coordinator.goToNext()
            }
            .padding(.horizontal, 24).padding(.bottom, 32)
            .opacity(showContent ? 1 : 0).offset(y: showContent ? 0 : 30)
            .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.4), value: showContent)
        }
        .background(InteractiveBackground())
        .onAppear {
            entries = assessmentData.healthcareProviders
            isTextFieldFocused = true
            withAnimation { showContent = true }
        }
    }
    
    private func addEntry() {
        let trimmed = currentEntry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        entries.append(trimmed)
        currentEntry = ""
    }
}

#Preview {
    let manager = AssessmentDataManager()
    HealthcareProviders()
        .environmentObject(manager)
        .environmentObject(AssessmentCoordinator(dataManager: manager))
}//
//  HealthcareProviders.swift
//  Peezy 4.0
//
//  Created by Adam Powell on 2/10/26.
//

