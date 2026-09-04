import FirebaseFirestore

enum UserKnowledgeSource: String {
    case assessment
    case settings
}

enum UserKnowledgeService {
    static func merge(
        _ values: [String: Any],
        source: UserKnowledgeSource,
        userId: String
    ) async throws {
        let entries = values.mapValues { value in
            [
                "value": value,
                "source": source.rawValue,
                "updatedAt": FieldValue.serverTimestamp()
            ] as [String: Any]
        }

        // §5:543-546: transactionally read the root, require reset absence,
        // preserve an existing matching stamp or create/stamp the current epoch,
        // upgrade an unstamped document only at epoch 0, and reject drift.
        let db = try await FirestoreRuntime.provider.acquire().firestore
        let rootRef = db.collection("users").document(userId)
        let knowledgeRef = db.collection("userKnowledge").document(userId)
        try await db.runTypedTransaction { transaction in
            let root = try transaction.getDocument(rootRef)
            let epoch = try TaskGenerationEpochStamp.effectiveRootEpoch(root.data(), requireResetAbsent: true)
            let existing = try transaction.getDocument(knowledgeRef)
            if existing.exists {
                if let raw = existing.data()?[TaskGenerationEpochStamp.fieldName] {
                    guard let stored = TaskGenerationEpochStamp.safeInteger(raw) else { throw TaskGenerationEpochError.malformedStamp }
                    guard stored == epoch else { throw TaskGenerationEpochError.stampMismatch(stored: stored, root: epoch) }
                } else if epoch != 0 {
                    throw TaskGenerationEpochError.unstampedAtLaterEpoch(root: epoch)
                }
            }
            transaction.setData(
                ["entries": entries, TaskGenerationEpochStamp.fieldName: epoch],
                forDocument: knowledgeRef,
                merge: true
            )
        }
    }
}
