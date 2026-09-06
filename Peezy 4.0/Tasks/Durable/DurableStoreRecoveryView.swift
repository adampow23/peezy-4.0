import Combine
import SwiftUI

// S4 (briefs/S4_BRIEF.md): the recovery surface (C9.7.13 "Recovery surface" rule): overlays blocked-store and deletion
// actions and the reset epoch-conflict options over a surface that mounts with every store blocked; it never turns an
// empty-required-set callable into a four-store dependency. Every action reaches its owner only through the driver, the
// deletion coordinator, or the completion presenter. Unmounted: S7 constructs and publishes it in `PeezyV1App`.

// MARK: - Pure presentation (tested without SwiftUI)

/// One actionable control: the C9.7.2 `availableActions` order and the C9.7.12 public action names.
struct RecoverySurfaceAction: Equatable, Identifiable, Sendable {
    let store: RecoveryStore
    let title: String
    let action: RecoveryAction
    let expectation: RecoveryExpectation
    /// `resolve` is enabled only once every decision group carries a choice.
    let enabled: Bool

    var id: String { "\(store.rawValue)/\(action.name)" }
}

/// One `reset_epoch_conflict` option; only the actionable (numerically smallest) epoch is enabled (C9.5.18).
struct RecoveryEpochOption: Equatable, Identifiable, Sendable {
    let expectedTaskGenerationEpoch: Int
    let phase: ResetRowPhase
    let recoveryAction: ResetRecoveryAction
    let recoveryStateDigest: String
    let enabled: Bool

    var id: Int { expectedTaskGenerationEpoch }
}

enum RecoverySurfacePresentation {
    /// The C9.7.12 public action names.
    static func title(_ action: RecoveryAction) -> String {
        switch action {
        case .recover: return "Recover"
        case .merge: return "Merge"
        case .discardQuarantine: return "Discard quarantine"
        case .retryCleanup: return "Retry cleanup"
        case .reconcile, .foreignReconcile: return "Reconcile"
        case .resolve: return "Resolve"
        case .retry: return "Retry"
        case .repairInstallationIdentity: return "Repair installation identity"
        case .quarantineDoseBytes: return "Quarantine dose bytes"
        }
    }

    static func storeTitle(_ store: RecoveryStore) -> String {
        switch store {
        case .route: return "Route store"
        case .handoff: return "Handoff store"
        case .reset: return "Reset store"
        case .workflow: return "Workflow store"
        case .dose: return "Daily dose store"
        }
    }

    /// `"{store title}: {state}"`; the snapshot carries no account, path, or payload (C9.7.2 opacity).
    static func stateCopy(_ snapshot: BlockedSnapshot) -> String {
        "\(storeTitle(snapshot.store)): \(snapshot.state.replacingOccurrences(of: "_", with: " "))"
    }

    /// The typed action behind each `availableActions` literal, with the expectation the owner CASes.
    static func actions(for snapshot: BlockedSnapshot, foreignChoices: [String: String] = [:]) -> [RecoverySurfaceAction] {
        let store = snapshot.store
        let digest = snapshot.recoveryStateDigest
        func digestAction(_ action: RecoveryAction, enabled: Bool = true) -> RecoverySurfaceAction? {
            guard let digest else { return nil }
            return RecoverySurfaceAction(store: store, title: title(action), action: action, expectation: .digest(digest), enabled: enabled)
        }
        return snapshot.availableActions.compactMap { name -> RecoverySurfaceAction? in
            switch (name, snapshot) {
            case ("recover", _): return digestAction(.recover)
            case ("merge", _): return digestAction(.merge)
            case ("discard_quarantine", _): return digestAction(.discardQuarantine)
            case ("retry_cleanup", _): return digestAction(.retryCleanup)
            case ("reconcile", .receiptMismatch(_, _, let mismatch)): return digestAction(.reconcile(mismatchIdentityDigest: mismatch))
            case ("reconcile", .foreignInstallation): return digestAction(.foreignReconcile)
            case ("resolve", .foreignResolutionRequired(_, let resolutionDigest, _, let groups)):
                let choices = ForeignResolutionChoices.choices(groups: groups, selections: foreignChoices)
                return digestAction(.resolve(resolutionDigest: resolutionDigest, choices: ForeignResolutionChoices.elements(choices ?? [])), enabled: choices != nil)
            case ("retry", .storageIOUnavailable(_, let code)):
                let token = UnavailableToken(store: store, state: snapshot.state, errorCode: code.rawValue)
                return RecoverySurfaceAction(store: store, title: title(.retry(errorCode: code.rawValue)), action: .retry(errorCode: code.rawValue), expectation: .unavailable(token), enabled: true)
            case ("retry", .installationAuthorityUnavailable(let code)):
                let token = UnavailableToken(store: store, state: snapshot.state, errorCode: code.rawValue)
                return RecoverySurfaceAction(store: store, title: title(.retry(errorCode: code.rawValue)), action: .retry(errorCode: code.rawValue), expectation: .unavailable(token), enabled: true)
            case ("repair_installation_identity", .installationAuthorityInvalid):
                let token = UnavailableToken(store: store, state: snapshot.state, errorCode: "KEYCHAIN_VALUE_INVALID")
                return RecoverySurfaceAction(store: store, title: title(.repairInstallationIdentity), action: .repairInstallationIdentity, expectation: .unavailable(token), enabled: true)
            case ("quarantine_dose_bytes", .doseMalformed): return digestAction(.quarantineDoseBytes)
            case ("recover_epoch", _): return nil // rendered as epoch options
            default: return nil
            }
        }
    }

    /// The ordered `reset_epoch_conflict` options; later epochs are displayed but disabled.
    static func epochOptions(for snapshot: BlockedSnapshot) -> [RecoveryEpochOption] {
        guard case let .resetEpochConflict(digest, actionable, occupants) = snapshot else { return [] }
        return occupants.map { RecoveryEpochOption(expectedTaskGenerationEpoch: $0.expectedTaskGenerationEpoch, phase: $0.phase, recoveryAction: $0.recoveryAction, recoveryStateDigest: digest, enabled: $0.expectedTaskGenerationEpoch == actionable) }
    }

    /// The `{date}` copy of the guarding presentation, the queued/blocked copy with their Retry.
    static func deletionCopy(_ presentation: AccountDeletionPresentationV1) -> (copy: String, retry: Bool) {
        switch presentation {
        case .queued: return (AccountDeletionCompletionCopy.queued, true)
        case let .blocked(reason):
            let copy = reason == .localPrivacyPurgeFailed ? AccountDeletionCompletionCopy.telemetryRelaunch : "Deletion is blocked (\(reason.rawValue)). Try again."
            return (copy, true)
        case let .guarding(authGuardAfter): return (AccountDeletionPresentationV1.guarding(authGuardAfter: authGuardAfter).map["copy"] as? String ?? "", false)
        case .completion: return ("", false)
        }
    }
}

/// The C2.5 completion surface: exact title, body, button, and the manual-required paragraphs with their frozen links in
/// Apple-then-Google order.
struct CompletionSurfaceContent: Equatable, Sendable {
    struct Section: Equatable, Sendable {
        let provider: CompletionProvider
        let paragraph: String
        let linkTitle: String
        let url: URL
    }

    let title: String
    let body: String
    let button: String
    let sections: [Section]

    static func content(for result: CompletionResultV1) -> CompletionSurfaceContent {
        switch result {
        case .completed:
            let sections: [Section] = result.manualProviders.map { provider in
                switch provider {
                case .apple: return Section(provider: .apple, paragraph: AccountDeletionCompletionCopy.appleManual, linkTitle: AccountDeletionCompletionCopy.appleInstructions, url: AccountDeletionCompletionCopy.appleURL)
                case .google: return Section(provider: .google, paragraph: AccountDeletionCompletionCopy.googleManual, linkTitle: AccountDeletionCompletionCopy.googleInstructions, url: AccountDeletionCompletionCopy.googleURL)
                }
            }
            return CompletionSurfaceContent(title: AccountDeletionCompletionCopy.title, body: AccountDeletionCompletionCopy.body, button: AccountDeletionCompletionCopy.button, sections: sections)
        case .localCleared:
            return CompletionSurfaceContent(title: AccountDeletionCompletionCopy.title, body: AccountDeletionCompletionCopy.localCleared, button: AccountDeletionCompletionCopy.button, sections: [])
        case .remoteUnconfirmed:
            return CompletionSurfaceContent(title: AccountDeletionCompletionCopy.remoteUnconfirmedTitle, body: AccountDeletionCompletionCopy.remoteUnconfirmed, button: AccountDeletionCompletionCopy.button, sections: [])
        }
    }
}

// MARK: - The surface model: every action through its owner's seam

@MainActor
final class DurableStoreRecoveryModel: ObservableObject {
    @Published private(set) var classifications: [RecoveryStore: RecoveryClassification] = [:]
    @Published private(set) var deletion: AccountDeletionPresentationV1?
    @Published private(set) var completion: CompletionSnapshotV1?
    @Published private(set) var isBusy = false
    @Published private(set) var lastResult: RecoveryResult?
    @Published var foreignChoices: [String: String] = [:]
    /// Bumped by every action so a slow `refresh` finishing afterwards never overwrites the post-action state.
    private var refreshGeneration = 0

    private let driver: DurableStoreRecoveryDriver
    private let epochRecovery: (any ResetEpochConflictRecovering)?
    private let coordinator: DurableStoreRecoveryCoordinator?
    private let presenter: (any AccountDeletionCompletionPresenting)?

    init(driver: DurableStoreRecoveryDriver, epochRecovery: (any ResetEpochConflictRecovering)? = nil, coordinator: DurableStoreRecoveryCoordinator? = nil, presenter: (any AccountDeletionCompletionPresenting)? = nil) {
        self.driver = driver
        self.epochRecovery = epochRecovery
        self.coordinator = coordinator
        self.presenter = presenter
    }

    /// The blocked stores in the frozen order route, handoff, reset, workflow, dose.
    var blocked: [(store: RecoveryStore, snapshot: BlockedSnapshot)] {
        RecoveryStore.allCases.compactMap { store in
            guard case let .blocked(snapshot)? = classifications[store] else { return nil }
            return (store, snapshot)
        }
    }

    func refresh() async {
        let generation = refreshGeneration
        let classified = await driver.classifyAll()
        let presentation = await coordinator?.currentPresentation()
        var snapshot = await presenter?.current()
        if case let .completion(pending)? = presentation { snapshot = pending }
        guard !Task.isCancelled, generation == refreshGeneration else { return }
        classifications = classified
        deletion = presentation
        completion = snapshot
    }

    @discardableResult
    func perform(_ control: RecoverySurfaceAction) async -> RecoveryResult {
        guard !isBusy else { return .busy(store: control.store) }
        isBusy = true
        refreshGeneration += 1
        defer { isBusy = false }
        let result = await driver.perform(store: control.store, action: control.action, expecting: control.expectation)
        lastResult = result
        classifications = await driver.classifications
        return result
    }

    /// The selected epoch option, only its own row's reducer branch (C9.5.18).
    @discardableResult
    func recover(_ option: RecoveryEpochOption) async -> RecoveryResult {
        guard option.enabled, let epochRecovery, !isBusy else { return .unavailable(store: .reset) }
        isBusy = true
        refreshGeneration += 1
        defer { isBusy = false }
        let result = await epochRecovery.recoverEpoch(recoveryStateDigest: option.recoveryStateDigest, expectedTaskGenerationEpoch: option.expectedTaskGenerationEpoch, expectedPhase: option.phase, action: option.recoveryAction)
        lastResult = result
        _ = await driver.classify(.reset)
        classifications = await driver.classifications
        return result
    }

    @discardableResult
    func retryDeletion() async -> AccountDeletionDispatchResult? {
        guard let coordinator, !isBusy else { return nil }
        isBusy = true
        refreshGeneration += 1
        defer { isBusy = false }
        let result = await coordinator.retry()
        deletion = await coordinator.currentPresentation()
        if case let .settled(.completion(snapshot)) = result { completion = snapshot }
        return result
    }

    @discardableResult
    func acknowledgeCompletion() async -> CompletionAcknowledgeResult? {
        guard let presenter, let completion, !isBusy else { return nil }
        isBusy = true
        refreshGeneration += 1
        defer { isBusy = false }
        let result = await presenter.acknowledge(expectedGenerationId: completion.generationId, expectedSHA256: completion.sha256)
        if result == .acknowledged {
            self.completion = nil
            deletion = await coordinator?.currentPresentation()
        }
        return result
    }

    @discardableResult
    func open(_ provider: CompletionProvider) async -> CompletionOpenResult? {
        guard let presenter, let completion, !isBusy else { return nil }
        isBusy = true
        defer { isBusy = false }
        return await presenter.open(expectedGenerationId: completion.generationId, expectedSHA256: completion.sha256, provider: provider)
    }
}

// MARK: - Views

struct DurableStoreRecoveryView: View {
    @ObservedObject var model: DurableStoreRecoveryModel

    var body: some View {
        List {
            if let completion = model.completion {
                AccountDeletionCompletionSurface(content: CompletionSurfaceContent.content(for: completion.result), open: { provider in _ = await model.open(provider) }, done: { _ = await model.acknowledgeCompletion() })
            } else if let deletion = model.deletion, !deletion.isCompletion {
                Section("Account deletion") {
                    let copy = RecoverySurfacePresentation.deletionCopy(deletion)
                    Text(copy.copy)
                    if copy.retry {
                        Button("Retry") { Task { await model.retryDeletion() } }.disabled(model.isBusy).accessibilityIdentifier("deletion.retry")
                    }
                }
            }
            ForEach(model.blocked, id: \.store) { entry in
                Section(RecoverySurfacePresentation.stateCopy(entry.snapshot)) {
                    ForEach(RecoverySurfacePresentation.epochOptions(for: entry.snapshot)) { option in
                        Button("Epoch \(option.expectedTaskGenerationEpoch): \(option.recoveryAction.rawValue.replacingOccurrences(of: "_", with: " "))") { Task { await model.recover(option) } }
                            .disabled(!option.enabled || model.isBusy)
                    }
                    if case let .foreignResolutionRequired(_, _, _, groups) = entry.snapshot {
                        let labels = ForeignResolutionChoices.displayLabels(groups)
                        ForEach(Array(zip(labels, groups)), id: \.1.decisionDigest) { label, group in
                            Picker(label, selection: Binding(get: { model.foreignChoices[group.decisionDigest] ?? "" }, set: { model.foreignChoices[group.decisionDigest] = $0 })) {
                                Text("Choose").tag("")
                                Text("Continue").tag("continue")
                                Text("Restart").tag("restart")
                            }
                        }
                    }
                    ForEach(RecoverySurfacePresentation.actions(for: entry.snapshot, foreignChoices: model.foreignChoices)) { control in
                        Button(control.title) { Task { await model.perform(control) } }.disabled(!control.enabled || model.isBusy).accessibilityIdentifier("recovery.\(control.id)")
                    }
                }
            }
        }
        .task { await model.refresh() }
    }
}

/// The C2.5 surface: title, body, the manual-required paragraphs with their links (Apple then Google), and the sole
/// consuming `Done`. Links never consume.
struct AccountDeletionCompletionSurface: View {
    let content: CompletionSurfaceContent
    let open: @Sendable (CompletionProvider) async -> Void
    let done: @Sendable () async -> Void

    var body: some View {
        Section(content.title) {
            Text(content.body)
            ForEach(content.sections, id: \.provider) { section in
                Text(section.paragraph)
                Button(section.linkTitle) { Task { await open(section.provider) } }
            }
            Button(content.button) { Task { await done() } }.accessibilityIdentifier("completion.done")
        }
    }
}
