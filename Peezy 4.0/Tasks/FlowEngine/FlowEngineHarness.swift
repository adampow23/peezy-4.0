//
//  FlowEngineHarness.swift
//  Peezy 4.0
//
//  DEBUG-only validation harness (Spec 04 Phase A). Lets the phase validator
//  drive FlowEngineView against local definitions BEFORE the router lands
//  (Phase C) and before flowDefinitions is seeded (the Phase B/C deploy
//  batch). Activated purely by launch environment — inert otherwise:
//
//    simctl launch --console <udid> <bundle> \
//      FLOW_HARNESS_WORKFLOW=manage_bank \
//      FLOW_DEFS_PATH=/path/to/functions/flowDefinitionsData.json \
//      FLOW_HARNESS_TASKID=MANAGE_BANK \
//      FLOW_HARNESS_CURRENT_ADDR="..." FLOW_HARNESS_NEW_ADDR="..." \
//      FLOW_HARNESS_MOVEDATE=2026-07-30
//
//  The simulator process can read host paths, so FLOW_DEFS_PATH points
//  straight at the repo JSON. Firebase is configured by PeezyV1App as usual,
//  so the keychain session (test bot) backs real Firestore persistence for
//  the resume criterion.
//

#if DEBUG
import SwiftUI
import FirebaseAuth

struct FlowEngineHarness: View {

    static var isActive: Bool {
        ProcessInfo.processInfo.environment["FLOW_HARNESS_WORKFLOW"] != nil
    }

    @State private var definition: FlowDefinition?
    @State private var loadError: String?
    @State private var terminal: String?

    private var env: [String: String] { ProcessInfo.processInfo.environment }

    var body: some View {
        ZStack {
            if let definition {
                FlowEngineView(
                    definition: definition,
                    userId: Auth.auth().currentUser?.uid ?? "",
                    taskId: env["FLOW_HARNESS_TASKID"] ?? "",
                    inputs: FlowInputs(
                        currentAddress: env["FLOW_HARNESS_CURRENT_ADDR"] ?? "1842 Oak Park Ave, Kansas City, MO 64108",
                        newAddress: env["FLOW_HARNESS_NEW_ADDR"] ?? "4201 Main St, Denver, CO 80205",
                        moveDate: harnessMoveDate
                    ),
                    onComplete: { terminal = "complete" },
                    onDismiss: { terminal = "dismiss" },
                    onStatusAction: { action in terminal = "status_\(action)" }
                )
            } else if let loadError {
                Text(loadError)
                    .font(.system(size: 15, weight: .medium))
                    .multilineTextAlignment(.center)
                    .padding(40)
                    .accessibilityIdentifier("harness.error")
            } else {
                ProgressView()
                    .accessibilityIdentifier("harness.loading")
            }

            if let terminal {
                VStack {
                    Text("TERMINAL: \(terminal)")
                        .font(.system(size: 13, weight: .bold))
                        .padding(8)
                        .background(Color.black.opacity(0.75))
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                        .accessibilityIdentifier("harness.terminal")
                    Spacer()
                }
                .padding(.top, 60)
                .allowsHitTesting(false)
            }
        }
        .onAppear { load() }
    }

    private var harnessMoveDate: Date {
        if let raw = env["FLOW_HARNESS_MOVEDATE"] {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]
            if let date = formatter.date(from: raw) { return date }
        }
        return Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
    }

    private func load() {
        guard definition == nil else { return }
        guard let workflowId = env["FLOW_HARNESS_WORKFLOW"],
              let defsPath = env["FLOW_DEFS_PATH"] else {
            loadError = "FLOW_HARNESS_WORKFLOW / FLOW_DEFS_PATH not set"
            return
        }
        // Read off the main thread — a host-filesystem path can block on
        // sandbox/TCC checks and a synchronous read here freezes first render.
        // Validators should stage the JSON inside the app container
        // ($(simctl get_app_container ...)/tmp) rather than a host user dir.
        Task.detached(priority: .userInitiated) {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: defsPath))
                let definitions = try JSONDecoder().decode([FlowDefinition].self, from: data)
                await MainActor.run {
                    guard let match = definitions.first(where: { $0.workflowId == workflowId }) else {
                        loadError = "No definition for \(workflowId) in \(defsPath)"
                        return
                    }
                    FlowDefinitionStore.shared.insert(match)
                    definition = match
                }
            } catch {
                await MainActor.run {
                    loadError = "Failed to load definitions: \(error.localizedDescription)"
                }
            }
        }
    }
}
#endif
