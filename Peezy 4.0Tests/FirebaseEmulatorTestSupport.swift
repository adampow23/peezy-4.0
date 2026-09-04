import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import Foundation
import Testing
@testable import Peezy_4_0

/// S1 (briefs/S1_BRIEF.md, scope item 4): points the test host's default
/// FirebaseApp at the local Firebase emulators. Emulator only — the project id
/// is the demo id the emulators accept, and nothing here can reach production.
///
/// The app's AppDelegate skips `FirebaseApp.configure()` under XCTest, so the
/// test target configures the default app itself, once, from the
/// `TEST_RUNNER_`-forwarded hosts that scripts/test-emulator.sh exports.
enum FirebaseEmulator {
    static let projectID = "demo-peezy-phase1"

    struct Hosts: Sendable, Equatable {
        let firestore: String   // "host:port"
        let auth: String?       // "host:port"
    }

    /// Present only when the suite runs under scripts/test-emulator.sh.
    static let hosts: Hosts? = {
        let env = ProcessInfo.processInfo.environment
        guard let firestore = env["FIRESTORE_EMULATOR_HOST"], !firestore.isEmpty else { return nil }
        let auth = env["FIREBASE_AUTH_EMULATOR_HOST"].flatMap { $0.isEmpty ? nil : $0 }
        return Hosts(firestore: firestore, auth: auth)
    }()

    static var isConfigured: Bool { hosts != nil }

    struct Unavailable: Error, CustomStringConvertible {
        var description: String { "FIRESTORE_EMULATOR_HOST is unset; run scripts/test-emulator.sh" }
    }

    private static let configureOnce: Result<Hosts, Unavailable> = {
        guard let hosts else { return .failure(Unavailable()) }
        if FirebaseApp.app() == nil {
            let options = FirebaseOptions(googleAppID: "1:000000000000:ios:0000000000000000", gcmSenderID: "000000000000")
            options.projectID = projectID
            options.apiKey = "AIzaSyEmulatorOnlyKey000000000000000000"  // shape-valid placeholder; emulators ignore it
            FirebaseApp.configure(options: options)
        }
        let settings = FirestoreSettings()
        settings.host = hosts.firestore
        settings.isSSLEnabled = false
        settings.cacheSettings = MemoryCacheSettings()
        Firestore.firestore().settings = settings
        if let auth = hosts.auth, let colon = auth.lastIndex(of: ":"),
           let port = Int(auth[auth.index(after: colon)...]) {
            Auth.auth().useEmulator(withHost: String(auth[..<colon]), port: port)
        }
        return .success(hosts)
    }()

    /// The default-app Firestore, bound to the emulator. Throws when the
    /// emulator is not configured so a suite fails loudly instead of touching
    /// a real backend.
    static func firestore() throws -> Firestore {
        _ = try configureOnce.get()
        return Firestore.firestore()
    }

    /// Creates a fresh email/password user in the Auth emulator and signs in,
    /// so owner-scoped rules evaluate against a real `request.auth.uid`.
    @discardableResult
    static func signInFreshUser() async throws -> String {
        _ = try configureOnce.get()
        let email = "s1-\(UUID().uuidString.lowercased())@example.com"
        let result = try await Auth.auth().createUser(withEmail: email, password: "emulator-only-password")
        return result.user.uid
    }

    static func signOut() throws {
        _ = try configureOnce.get()
        try Auth.auth().signOut()
    }

    /// Deletes every document in the emulator's default database (REST endpoint
    /// the emulator exposes for exactly this purpose).
    static func clearFirestore() async throws {
        let hosts = try configureOnce.get()
        var request = URLRequest(url: URL(string: "http://\(hosts.firestore)/emulator/v1/projects/\(projectID)/databases/(default)/documents")!)
        request.httpMethod = "DELETE"
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw Unavailable()
        }
    }

    // MARK: - Admin writes (rules bypass) for seeding fixtures

    /// Replaces a document through the emulator's REST surface with the
    /// `Bearer owner` token the emulator accepts, bypassing security rules.
    /// Supported values: String, Int, Bool, Double, Date, [Any], [String: Any], NSNull.
    static func adminSet(_ path: String, _ fields: [String: Any]) async throws {
        let hosts = try configureOnce.get()
        var request = URLRequest(url: URL(string: "http://\(hosts.firestore)/v1/projects/\(projectID)/databases/(default)/documents/\(path)")!)
        request.httpMethod = "PATCH"
        request.setValue("Bearer owner", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["fields": fields.mapValues(restValue)])
        let (body, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AdminWriteFailed(body: String(decoding: body, as: UTF8.self))
        }
    }

    struct AdminWriteFailed: Error, CustomStringConvertible {
        let body: String
        var description: String { "emulator admin write failed: \(body)" }
    }

    private static let rfc3339: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func restValue(_ value: Any) -> [String: Any] {
        switch value {
        case let string as String: return ["stringValue": string]
        case let bool as Bool: return ["booleanValue": bool]
        case let int as Int: return ["integerValue": String(int)]
        case let double as Double: return ["doubleValue": double]
        case let date as Date: return ["timestampValue": rfc3339.string(from: date)]
        case let array as [Any]: return ["arrayValue": ["values": array.map(restValue)]]
        case let map as [String: Any]: return ["mapValue": ["fields": map.mapValues(restValue)]]
        case is NSNull: return ["nullValue": NSNull()]
        default: fatalError("unsupported fixture value: \(value)")
        }
    }
}
