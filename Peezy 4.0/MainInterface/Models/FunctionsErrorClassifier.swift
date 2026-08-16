import FirebaseFunctions
import Foundation

nonisolated enum FunctionsErrorClassification: Equatable {
    case movePassRequired
}

nonisolated enum FunctionsErrorClassifier {
    static func classify(_ error: Error) -> FunctionsErrorClassification? {
        let functionsError = error as NSError
        guard functionsError.domain == FunctionsErrorDomain,
              FunctionsErrorCode(rawValue: functionsError.code) == .permissionDenied else {
            return nil
        }

        let details = functionsError.userInfo[FunctionsErrorDetailsKey]
        let reason = (details as? [String: Any])?["reason"] as? String
            ?? (details as? NSDictionary)?["reason"] as? String

        if reason == "move-pass-required"
            || functionsError.localizedDescription == "Move Pass required" {
            return .movePassRequired
        }
        return nil
    }
}
