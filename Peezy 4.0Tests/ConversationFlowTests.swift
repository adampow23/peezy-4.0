//
//  ConversationFlowTests.swift
//  Peezy 4.0Tests
//
//  Spec 09 Phase 4: additive FlowDefinition decode, spawn resolution
//  (guards, per-selection expansion, zero-spawn), and the remembered-answer
//  (skipIfKnown) advance walk.
//

import Foundation
import Testing
@testable import Peezy_4_0

struct ConversationFlowTests {

    private func decodeDefinition(_ json: String) throws -> FlowDefinition {
        try JSONDecoder().decode(FlowDefinition.self, from: Data(json.utf8))
    }

    // MARK: - Additive decode

    @Test func existingDefinitionShapeDecodesUnchanged() throws {
        let json = #"""
        {
          "workflowId": "update_gym",
          "taskTitle": "Handle my gym",
          "steps": [
            { "id": "intro", "kind": "title", "icon": "figure.run", "next": "handling" },
            { "id": "handling", "kind": "decision",
              "branches": [ { "value": "peezy", "next": "summary" } ],
              "next": "summary" },
            { "id": "summary", "kind": "summary" }
          ]
        }
        """#
        let definition = try decodeDefinition(json)
        #expect(definition.steps.count == 3)
        #expect(definition.steps.allSatisfy { $0.skipIfKnown == nil && $0.spawns == nil })
    }

    @Test func spawnStepDecodesAdditively() throws {
        let json = #"""
        {
          "workflowId": "update_auto_insurance",
          "taskTitle": "Auto insurance",
          "steps": [
            { "id": "intent", "kind": "select", "skipIfKnown": "insurance_intent",
              "options": [ { "id": "update", "label": "Update my policy", "icon": "car" } ],
              "next": "wrap" },
            { "id": "wrap", "kind": "spawn",
              "spawns": [
                { "taskId": "AUTO_INSURANCE_UPDATE", "when": { "intent": "update" } },
                { "taskId": "UPDATE_INSTITUTION", "perSelectionFrom": "provider" }
              ] }
          ]
        }
        """#
        let definition = try decodeDefinition(json)
        let wrap = try #require(definition.step(withId: "wrap"))
        #expect(wrap.kind == .spawn)
        #expect(definition.step(withId: "intent")?.skipIfKnown == "insurance_intent")
        #expect(wrap.spawns == [
            FlowSpawnDef(taskId: "AUTO_INSURANCE_UPDATE", when: ["intent": "update"], perSelectionFrom: nil),
            FlowSpawnDef(taskId: "UPDATE_INSTITUTION", when: nil, perSelectionFrom: "provider")
        ])
    }

    // MARK: - Guarded selection

    @Test func whenGuardSelectsSpawnByRecordedIntent() {
        let spawns = [
            FlowSpawnDef(taskId: "AUTO_INSURANCE_UPDATE", when: ["intent": "update"], perSelectionFrom: nil),
            FlowSpawnDef(taskId: "AUTO_INSURANCE_SHOP", when: ["intent": "shop"], perSelectionFrom: nil)
        ]
        let resolved = FlowEngineView.resolveSpawns(spawns, answers: ["intent": ["shop"]], steps: [])
        #expect(resolved.count == 1)
        #expect(resolved.first?.taskId == "AUTO_INSURANCE_SHOP")
        #expect(resolved.first?.titleParams == nil)
    }

    // MARK: - Per-selection expansion

    @Test func perSelectionExpandsWithOptionLabels() throws {
        let providerStep = try JSONDecoder().decode(FlowStep.self, from: Data(#"""
        {
          "id": "provider", "kind": "select",
          "options": [
            { "id": "chase", "label": "Chase", "icon": "building.columns" },
            { "id": "ally", "label": "Ally", "icon": "building.columns" },
            { "id": "fidelity", "label": "Fidelity", "icon": "building.columns" }
          ]
        }
        """#.utf8))
        let spawns = [FlowSpawnDef(taskId: "UPDATE_INSTITUTION", when: nil, perSelectionFrom: "provider")]
        let resolved = FlowEngineView.resolveSpawns(
            spawns,
            answers: ["provider": ["chase", "ally", "fidelity"]],
            steps: [providerStep]
        )
        #expect(resolved.count == 3)
        #expect(resolved.map { $0.titleParams?["institution"] } == ["Chase", "Ally", "Fidelity"])
        #expect(resolved.allSatisfy { $0.taskId == "UPDATE_INSTITUTION" })
    }

    // MARK: - Zero spawn

    @Test func unsatisfiedGuardsResolveToZeroSpawns() {
        let guarded = [
            FlowSpawnDef(taskId: "RETURN_ISP_EQUIPMENT", when: ["current": "yes"], perSelectionFrom: nil)
        ]
        #expect(FlowEngineView.resolveSpawns(guarded, answers: ["current": ["no"]], steps: []).isEmpty)

        let unselected = [
            FlowSpawnDef(taskId: "UPDATE_INSTITUTION", when: nil, perSelectionFrom: "provider")
        ]
        #expect(FlowEngineView.resolveSpawns(unselected, answers: [:], steps: []).isEmpty)
    }

    // MARK: - Remembered-step advance

    @Test func knownAnswerStepsAdoptAndAdvance() throws {
        let definition = try decodeDefinition(#"""
        {
          "workflowId": "setup_internet",
          "taskTitle": "Internet",
          "steps": [
            { "id": "current", "kind": "select", "skipIfKnown": "isp_current",
              "options": [
                { "id": "yes", "label": "Yes", "icon": "wifi" },
                { "id": "no", "label": "No", "icon": "wifi.slash" }
              ],
              "branches": [ { "value": "no", "next": "wrap" } ],
              "next": "speed" },
            { "id": "speed", "kind": "select", "skipIfKnown": "isp_speed", "next": "wrap" },
            { "id": "wrap", "kind": "spawn" }
          ]
        }
        """#)

        // Firestore flattening: NSNumber numerics/bools become flat strings.
        let known = MoveAnswersStore.flattened([
            "isp_current": "yes",
            "isp_speed": NSNumber(value: 300),
            "has_car": true
        ])
        #expect(known["isp_speed"] == "300")
        #expect(known["has_car"] == "true")

        var answers: [String: [String]] = [:]
        let landing = FlowEngineView.resolveKnownAnswerSkips(
            from: "current",
            steps: definition.steps,
            knownAnswers: known,
            answers: &answers
        )
        #expect(landing == "wrap")
        #expect(answers["current"] == ["yes"])
        #expect(answers["speed"] == ["300"])

        // Branch semantics: a remembered "no" takes the branch past "speed".
        var branchAnswers: [String: [String]] = [:]
        let branchLanding = FlowEngineView.resolveKnownAnswerSkips(
            from: "current",
            steps: definition.steps,
            knownAnswers: ["isp_current": "no"],
            answers: &branchAnswers
        )
        #expect(branchLanding == "wrap")
        #expect(branchAnswers["speed"] == nil)
    }
}
