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

        try await Firestore.firestore()
            .collection("userKnowledge")
            .document(userId)
            .setData(["entries": entries], merge: true)
    }
}
