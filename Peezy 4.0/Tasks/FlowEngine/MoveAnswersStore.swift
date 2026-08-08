//
//  MoveAnswersStore.swift
//  Peezy 4.0
//
//  Remembered conversation answers (Spec 09 Phase 4). One-shot direct read of
//  users/{uid}/moveAnswers/answers, flattened to strings so skipIfKnown steps
//  can adopt values with the engine's branch semantics. Cached per session.
//

import Foundation
import FirebaseFirestore

@Observable
@MainActor
final class MoveAnswersStore {
    static let shared = MoveAnswersStore()

    private(set) var answers: [String: String] = [:]
    private var loadedUserId: String?

    /// One-shot fetch, cached for the session. A missing doc or failed read
    /// leaves the store empty — every skipIfKnown step simply renders.
    func load(userId: String) async {
        guard !userId.isEmpty, loadedUserId != userId else { return }
        do {
            let snapshot = try await Firestore.firestore()
                .collection("users").document(userId)
                .collection("moveAnswers").document("answers")
                .getDocument()
            answers = Self.flattened(snapshot.data() ?? [:])
            loadedUserId = userId
        } catch {
            print("⚠️ Move answers read failed: \(error.localizedDescription)")
        }
    }

    func value(for key: String) -> String? {
        answers[key]
    }

    /// Firestore values arrive as strings or NSNumber (bool/int/double);
    /// everything else is dropped — the store is flat by contract.
    nonisolated static func flattened(_ data: [String: Any]) -> [String: String] {
        data.reduce(into: [:]) { result, entry in
            if let string = entry.value as? String {
                result[entry.key] = string
            } else if let number = entry.value as? NSNumber {
                result[entry.key] = number === kCFBooleanTrue || number === kCFBooleanFalse
                    ? (number.boolValue ? "true" : "false")
                    : number.stringValue
            }
        }
    }
}
