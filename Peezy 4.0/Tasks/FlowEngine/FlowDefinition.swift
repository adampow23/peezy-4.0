//
//  FlowDefinition.swift
//  Peezy 4.0
//
//  Config-driven flow model (Spec 04 Phase A). One definition per workflowId,
//  authored in functions/flowDefinitionsData.json, seeded to the Firestore
//  `flowDefinitions` collection. Signed-in clients read definitions directly;
//  getWorkflowQualifying remains a one-release fallback while the rules change
//  rolls out (Spec 05 Phase 0).
//
//  Expressiveness is capped at what the 38 templated flow screens actually
//  use: nine step kinds, value-keyed branches, and one conditional branch
//  form ({value, when, next} — the ManageBank-family find-decision routing).
//  Do not extend this model beyond an observed need.
//

import Foundation
import FirebaseFirestore
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
    var id: String
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

    // Row-generation (Spec 04 Phase B). Rows are stamped on the task doc as
    // `flowRows` by TaskGenerationService from the catalog's rowGeneration
    // config; definitions reference them three ways:
    /// Step included only when the task's rows contain this row id
    /// (e.g. the DMV registration section when hasVehicles).
    var requiresRow: String?
    /// Step expands into one chained instance per row (instance id
    /// "{rowId}.{stepId}" — also the answer key), config per row category.
    var forEachRow: Bool?
    var rowConfigs: [String: FlowRowConfig]?
    /// Summary-step labels for the {rowsList} substitution, keyed by row id.
    var rowLabels: [String: String]?
}

/// Per-category strings for a forEachRow step instance.
struct FlowRowConfig: Codable, Equatable {
    let question: String
    let placeholder: String
    let searchHint: String
}

/// One stamped row from the task doc's `flowRows` array.
struct FlowRow: Equatable {
    let id: String
    let category: String?

    init?(firestoreData: [String: Any]) {
        guard let id = firestoreData["id"] as? String else { return nil }
        self.id = id
        self.category = firestoreData["category"] as? String
    }
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

// MARK: - Row Resolution

extension FlowDefinition {
    /// Steps specialized to this task's stamped rows: forEachRow steps expand
    /// into one chained instance per matching row, requiresRow steps drop when
    /// their row is absent, and every next/branch target is re-aliased so the
    /// graph stays closed. Definitions without row features return unchanged.
    func resolvedSteps(rows: [FlowRow]) -> [FlowStep] {
        var result: [FlowStep] = []
        // original id → replacement target ("" = fall through to nothing)
        var alias: [String: String] = [:]

        for step in steps {
            if let required = step.requiresRow, !rows.contains(where: { $0.id == required }) {
                alias[step.id] = step.next ?? ""
                continue
            }

            if step.forEachRow == true {
                var instances: [FlowStep] = rows.compactMap { row in
                    guard let config = step.rowConfigs?[row.category ?? row.id] else { return nil }
                    var instance = step
                    instance.id = "\(row.id).\(step.id)"
                    instance.question = config.question
                    instance.placeholder = config.placeholder
                    instance.searchHint = config.searchHint
                    instance.forEachRow = nil
                    instance.rowConfigs = nil
                    return instance
                }
                guard !instances.isEmpty else {
                    alias[step.id] = step.next ?? ""
                    continue
                }
                for index in instances.indices {
                    instances[index].next = index + 1 < instances.count
                        ? instances[index + 1].id
                        : step.next
                }
                alias[step.id] = instances[0].id
                result.append(contentsOf: instances)
                continue
            }

            result.append(step)
        }

        guard !alias.isEmpty else { return result }

        func resolve(_ target: String?) -> String? {
            var current = target
            var hops = 0
            while let id = current, let replacement = alias[id], hops <= steps.count {
                current = replacement.isEmpty ? nil : replacement
                hops += 1
            }
            return current
        }

        for index in result.indices {
            result[index].next = resolve(result[index].next)
            if let branches = result[index].branches {
                result[index].branches = branches.map { branch in
                    FlowBranch(
                        value: branch.value,
                        when: branch.when,
                        next: resolve(branch.next) ?? branch.next
                    )
                }
            }
        }
        return result
    }
}

// MARK: - Definition Store

/// In-memory definition cache + direct Firestore fetch. The callable remains a
/// one-release fallback for a missing or failed direct read.
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

    /// Returns the cached definition or reads it directly from Firestore.
    /// Returns nil when the server has no definition for this workflowId —
    /// the router renders the coming-right-up card in that case.
    func definition(for workflowId: String) async -> FlowDefinition? {
        if let hit = cache[workflowId] { return hit }
        guard !workflowId.isEmpty else { return nil }

        do {
            let snapshot = try await Firestore.firestore()
                .collection("flowDefinitions")
                .document(workflowId)
                .getDocument()
            guard snapshot.exists else {
                print("⚠️ Flow definition missing from Firestore; using callable fallback: \(workflowId)")
                return await definitionFromCallable(workflowId: workflowId)
            }
            let definition = try snapshot.data(as: FlowDefinition.self)
            cache[workflowId] = definition
            print("✅ Flow definition direct Firestore read: \(workflowId)")
            return definition
        } catch {
            print("⚠️ Flow definition direct read failed; using callable fallback for \(workflowId): \(error.localizedDescription)")
        }

        return await definitionFromCallable(workflowId: workflowId)
    }

    private func definitionFromCallable(workflowId: String) async -> FlowDefinition? {
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
            print("⚠️ Flow definition callable fallback used: \(workflowId)")
            return definition
        } catch {
            print("⚠️ Flow definition fallback failed for \(workflowId): \(error.localizedDescription)")
            return nil
        }
    }
}
