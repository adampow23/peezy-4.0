import SwiftUI

private struct FlowProgressModifier: ViewModifier {
    @Environment(FlowExitCoordinator.self) private var coordinator

    let snapshot: FlowProgressSnapshot
    let onRestore: @MainActor (FlowProgressSnapshot) -> Void

    @State private var didRestore = false

    func body(content: Content) -> some View {
        content
            .disabled(!didRestore)
            .allowsHitTesting(didRestore)
            .task {
                let restored = await coordinator.restore()
                if restored.hasRecordedAnswers || !restored.path.isEmpty {
                    onRestore(restored)
                    await Task.yield()
                }
                didRestore = true
            }
            .onChange(of: snapshot) { _, newSnapshot in
                guard didRestore else { return }
                coordinator.persist(newSnapshot)
            }
    }
}

private struct FlowAnswerProbeModifier: ViewModifier {
    @Environment(FlowExitCoordinator.self) private var coordinator
    let probe: @MainActor () async -> Bool

    func body(content: Content) -> some View {
        content
            .onAppear {
                coordinator.registerAnswerProbe(probe)
            }
            .onDisappear {
                coordinator.unregisterAnswerProbe()
            }
    }
}

extension View {
    func resumableFlowProgress(
        path: [String],
        answers: [String: [String]],
        onRestore: @escaping @MainActor (FlowProgressSnapshot) -> Void
    ) -> some View {
        modifier(
            FlowProgressModifier(
                snapshot: FlowProgressSnapshot(path: path, answers: answers),
                onRestore: onRestore
            )
        )
    }

    func flowAnswerProbe(_ probe: @escaping @MainActor () async -> Bool) -> some View {
        modifier(FlowAnswerProbeModifier(probe: probe))
    }
}

enum FlowProgressCoding {
    static func encode(_ answers: [String: Set<String>]) -> [String: [String]] {
        answers.mapValues { $0.sorted() }
    }

    static func decode(_ answers: [String: [String]]) -> [String: Set<String>] {
        answers.mapValues(Set.init)
    }

    static func workflowAnswers(
        workflowId: String,
        setAnswers: [String: Set<String>]
    ) -> WorkflowAnswers {
        var result = WorkflowAnswers(workflowId: workflowId)
        result.answers = encode(setAnswers)
        return result
    }

    static func cardIndex(from path: [String], fallback: Int = 0) -> Int {
        guard let raw = path.last?.split(separator: ".").last,
              let index = Int(raw)
        else { return fallback }
        return index
    }
}
