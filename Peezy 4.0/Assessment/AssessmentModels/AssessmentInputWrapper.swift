//
//  AssessmentInputWrapper.swift
//  Peezy
//
//  Wraps any assessment input view with context animation.
//  The context header (and optional subheader) typewriters in at the top,
//  then the input controls slide up and fade in below.
//
//  Usage: Used ONCE in AssessmentFlowView around the question view switch.
//  Individual question views are unchanged — they just render their controls.
//

import SwiftUI

struct AssessmentInputWrapper<Content: View>: View {
    
    // MARK: - Configuration
    
    let step: AssessmentInputStep
    @ObservedObject var coordinator: AssessmentCoordinator
    @ViewBuilder let content: () -> Content
    
    // MARK: - State
    
    @State private var displayedHeaderText: String = ""
    @State private var displayedSubheaderText: String = ""
    @State private var headerComplete: Bool = false
    @State private var subheaderComplete: Bool = false
    @State private var showControls: Bool = false
    
    // MARK: - Animation Config
    
    private let typewriterSpeed: TimeInterval = 0.03
    
    // MARK: - Body
    
    var body: some View {
        let context = coordinator.inputContext(for: step)
        
        ZStack {
            Color.black
                .ignoresSafeArea()
            
            VStack(alignment: .leading, spacing: 0) {
                // Context area — typewriters in at the top
                VStack(alignment: .leading, spacing: 8) {
                    if !displayedHeaderText.isEmpty {
                        Text(displayedHeaderText)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .lineSpacing(4)
                    }
                    
                    if !displayedSubheaderText.isEmpty {
                        Text(displayedSubheaderText)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.6))
                            .lineSpacing(3)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 24)
                
                // Input controls — slide up and fade in after context finishes
                if showControls {
                    content()
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity
                        ))
                }
                
                Spacer(minLength: 0)
            }
        }
        .onAppear {
            startContextAnimation(context: context)
        }
        // Reset animation state when step changes (e.g. navigating back then forward)
        .onChange(of: step) { _, newStep in
            resetState()
            let newContext = coordinator.inputContext(for: newStep)
            startContextAnimation(context: newContext)
        }
    }
    
    // MARK: - Animation Logic
    
    private func startContextAnimation(context: InputContext) {
        // Phase 1: Typewrite the header
        typewrite(
            text: context.header,
            into: { self.displayedHeaderText = $0 }
        ) {
            headerComplete = true
            
            // Phase 2: If there's a subheader, typewrite it too
            if let subheader = context.subheader {
                typewrite(
                    text: subheader,
                    into: { self.displayedSubheaderText = $0 }
                ) {
                    subheaderComplete = true
                    revealControls()
                }
            } else {
                // No subheader — reveal controls immediately after header
                subheaderComplete = true
                revealControls()
            }
        }
    }
    
    private func revealControls() {
        withAnimation(.easeOut(duration: 0.4)) {
            showControls = true
        }
    }
    
    private func resetState() {
        displayedHeaderText = ""
        displayedSubheaderText = ""
        headerComplete = false
        subheaderComplete = false
        showControls = false
    }
    
    /// Typewriter effect — appends characters progressively.
    private func typewrite(
        text: String,
        into update: @escaping (String) -> Void,
        completion: @escaping () -> Void
    ) {
        let characters = Array(text)
        var index = 0
        var accumulated = ""
        
        func appendNext() {
            guard index < characters.count else {
                completion()
                return
            }
            
            // Batch 2 characters for smoother feel
            let batchSize = 2
            let end = min(index + batchSize, characters.count)
            accumulated += String(characters[index..<end])
            update(accumulated)
            index = end
            
            DispatchQueue.main.asyncAfter(deadline: .now() + typewriterSpeed) {
                appendNext()
            }
        }
        
        appendNext()
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    let dataManager = AssessmentDataManager()
    let coordinator = AssessmentCoordinator(dataManager: dataManager)
    
    AssessmentInputWrapper(step: .userName, coordinator: coordinator) {
        // Simulated question controls
        VStack(spacing: 16) {
            TextField("Your name", text: .constant(""))
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 24)
            
            Button("Continue") {}
                .font(.headline)
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
                .padding(.horizontal, 24)
        }
    }
}
#endif
