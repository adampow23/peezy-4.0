//
//  FlowDefinition.swift
//  Peezy 4.0
//
//  Config-driven flow model (Spec 04 Phase A). One definition per workflowId,
//  authored in functions/flowDefinitionsData.json, seeded to the Firestore
//  `flowDefinitions` collection, and served to the client through the deployed
//  getWorkflowQualifying callable (deployed rules have no client read on
//  flowDefinitions; the callable is the sanctioned transport until the
//  reconciled rules deploy — see Spec 04 Phase A report).
//
//  Expressiveness is capped at what the 38 templated flow screens actually
//  use: nine step kinds, value-keyed branches, and one conditional branch
//  form ({value, when, next} — the ManageBank-family find-decision routing).
//  Do not extend this model beyond an observed need.
//

import Foundation
import FirebaseFunctions

// MARK: - Flow Definition

struct FlowDefinition: Codable, Equatable {
    let workflowId: String
    /// Header/cover title, e.g. "Handle my bank account". 30-char cap per kit.
    let taskTitle: String
    /// Ordered steps. First element is the entry step.
    let steps: [FlowStep]

    func step(withId id: String) -> FlowStep? {
        steps.first { $0.id == id }
    }
}

// MARK: - Step

/// The nine card kinds the 38 templated flows render (kit component per case).
enum FlowStepKind: String, Codable, Equatable {
    case title           // TaskFlowTitleCard
    case info            // TaskFlowInfoCard
    case decision        // TaskFlowDecisionCard  (answer: ["peezy"] / ["self"])
    case select          // TaskFlowTilesCard, single-select
    case businessSearch  // TaskFlowBusinessSearchCard
    case confirmAddress  // TaskFlowConfirmAddressCard
    case confirmDate     // TaskFlowConfirmDateCard
    case summary         // TaskFlowSummaryCard (terminal: submits answers)
    case status          // TaskFlowStatusCard  (terminal: status action)
}

/// One card in a flow. `id` doubles as the answer key for answer-bearing
/// steps — ids like "handling_update" / "business_name" are load-bearing:
/// they keep the submitWorkflowAnswers payload byte-identical to the old
/// Swift screens. Config fields are optional; absent means the kit
/// component's own default (restated in FlowEngineView) applies.
struct FlowStep: Codable, Equatable {
    let id: String
    let kind: FlowStepKind

    // Navigation. `next` is the default successor (also drives the depth-card
    // count walk); `branches` route by the answer just given, first match wins.
    var next: String?
    var branches: [FlowBranch]?

    /// TaskStage raw value written via TaskActionService.setStage on entry.
    var stage: String?

    // title
    var icon: String?

    // info
    var infoTitle: String?
    var body: String?          // also: summary default body
    var primaryLabel: String?

    // decision / select / businessSearch / confirmAddress / confirmDate
    var question: String?
    var timeSaved: String?     // decision only
    var options: [FlowOptionDef]?  // select only

    // businessSearch
    var placeholder: String?
    var searchHint: String?

    // confirmAddress
    var addressSource: String? // "current" | "new"
    var displayIcon: String?

    // summary
    var subtext: String?
    var bodyVariants: [FlowSummaryVariant]?
}

/// Branch taken when the step's answer equals `value` and every `when`
/// pair matches an already-recorded answer (first element). Ordered;
/// first satisfied branch wins.
struct FlowBranch: Codable, Equatable {
    let value: String
    var when: [String: String]?
    let next: String
}

struct FlowOptionDef: Codable, Equatable {
    let id: String
    let label: String
    let icon: String
}

/// Summary body override: applies when every `when` pair matches a recorded
/// answer. Ordered; first match wins; falls back to the step's `body`.
struct FlowSummaryVariant: Codable, Equatable {
    let when: [String: String]
    let body: String
}

// MARK: - Definition Store

/// In-memory definition cache + callable fetch. Definitions live in the
/// Firestore `flowDefinitions` collection; the client fetches them through
/// getWorkflowQualifying (Firestore-first lookup, Phase B server edit)
/// because the deployed rules do not grant a direct client read.
@MainActor
final class FlowDefinitionStore {
    static let shared = FlowDefinitionStore()

    private var cache: [String: FlowDefinition] = [:]

    func cached(_ workflowId: String) -> FlowDefinition? {
        cache[workflowId]
    }

    func insert(_ definition: FlowDefinition) {
        cache[definition.workflowId] = definition
    }

    /// Returns the cached definition or fetches it via the callable.
    /// Returns nil when the server has no definition for this workflowId —
    /// the router renders the coming-right-up card in that case.
    func definition(for workflowId: String) async -> FlowDefinition? {
        if let hit = cache[workflowId] { return hit }

        do {
            let callable = Functions.functions().httpsCallable("getWorkflowQualifying")
            let result = try await callable.call(["workflowId": workflowId])
            guard let data = result.data as? [String: Any],
                  let definitionDict = data["flowDefinition"] as? [String: Any] else {
                return nil
            }
            let json = try JSONSerialization.data(withJSONObject: definitionDict)
            let definition = try JSONDecoder().decode(FlowDefinition.self, from: json)
            cache[workflowId] = definition
            return definition
        } catch {
            print("⚠️ Flow definition fetch failed for \(workflowId): \(error.localizedDescription)")
            return nil
        }
    }
}
