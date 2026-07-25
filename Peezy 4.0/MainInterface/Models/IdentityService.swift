//
//  IdentityService.swift
//  Peezy 4.0
//
//  Load/save/migrate for the identity doc (users/{uid}/identity/identity)
//  plus the shared address-distance geocoding used by both the assessment
//  completion path and Settings edits (the one sanctioned extraction from
//  AssessmentDataManager.computeDistanceAndInterstate, spec-01 Phase 2d).
//

import Foundation
import CoreLocation
import FirebaseAuth
import FirebaseFirestore

final class IdentityService {

    static let shared = IdentityService()

    private var db: Firestore { Firestore.firestore() }

    private func docRef(_ userId: String) -> DocumentReference {
        // §4 names the doc "users/{uid}/identity"; Firestore documents need an
        // even segment count, so the doc lives in a single-doc subcollection.
        db.collection("users").document(userId)
            .collection("identity").document("identity")
    }

    // MARK: - Load / Save

    func load(userId: String) async throws -> PeezyIdentity? {
        let snapshot = try await docRef(userId).getDocument()
        guard snapshot.exists, let data = snapshot.data() else { return nil }
        return PeezyIdentity(firestoreData: data)
    }

    func save(_ identity: PeezyIdentity, userId: String) async throws {
        try await docRef(userId).setData(identity.toFirestoreData())
    }

    /// Load-modify-save for single-field edits (Settings).
    func update(userId: String, _ mutate: (inout PeezyIdentity) -> Void) async throws {
        var identity = await loadOrMigrate(userId: userId)
            ?? PeezyIdentity(name: "", email: "")
        mutate(&identity)
        try await save(identity, userId: userId)
    }

    // MARK: - Migration

    /// Returns the identity doc, running the one-time migration when it is
    /// absent but assessment data exists. Returns nil only when there is
    /// nothing to build from (no identity doc and no assessment).
    func loadOrMigrate(userId: String) async -> PeezyIdentity? {
        if let existing = try? await load(userId: userId) {
            return existing
        }
        return await migrateIfNeeded(userId: userId)
    }

    /// If the identity doc is absent but assessment data exists, build it from
    /// the assessment doc + Auth email/displayName and write it (one-time).
    func migrateIfNeeded(userId: String) async -> PeezyIdentity? {
        guard let snapshot = try? await docRef(userId).getDocument() else { return nil }
        if snapshot.exists, let data = snapshot.data() {
            return PeezyIdentity(firestoreData: data)
        }

        guard let assessments = try? await db.collection("users").document(userId)
            .collection("user_assessments")
            .limit(to: 1)
            .getDocuments(),
            let assessmentDoc = assessments.documents.first
        else { return nil }

        let user = Auth.auth().currentUser
        let identity = Self.identity(
            fromAssessment: assessmentDoc.data(),
            email: user?.email,
            displayName: user?.displayName,
            moveDistanceMiles: nil
        )
        try? await save(identity, userId: userId)
        return identity
    }

    // MARK: - Building from assessment data

    /// Builds a PeezyIdentity from a getAllAssessmentData()-shaped dictionary.
    /// moveDistanceMiles is only known when geocoding just ran (assessment
    /// completion, Settings edits); migration passes nil.
    static func identity(
        fromAssessment data: [String: Any],
        email: String?,
        displayName: String?,
        moveDistanceMiles: Double?
    ) -> PeezyIdentity {
        var identity = PeezyIdentity(
            name: (data["userName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? displayName ?? "",
            email: email ?? ""
        )

        if let raw = data["currentAddress"] as? String, !raw.isEmpty {
            var address = PeezyAddress.parse(addressString: raw)
            if let unit = data["currentUnitNumber"] as? String, !unit.isEmpty {
                address.unit = unit
            }
            identity.currentAddress = address
        }
        if let raw = data["newAddress"] as? String, !raw.isEmpty {
            var address = PeezyAddress.parse(addressString: raw)
            if let unit = data["newUnitNumber"] as? String, !unit.isEmpty {
                address.unit = unit
            }
            identity.newAddress = address
        }

        if let timestamp = data["moveDate"] as? Timestamp {
            identity.moveDate = timestamp.dateValue()
        } else if let date = data["moveDate"] as? Date {
            identity.moveDate = date
        }

        identity.moveDistanceMiles = moveDistanceMiles
        if let interstate = data["isInterstate"] as? String, !interstate.isEmpty {
            identity.isInterstate = interstate == "Yes"
        }
        identity.newAddressPending = data["newAddressPending"] as? Bool
        identity.moveDatePending = data["moveDatePending"] as? Bool
        return identity
    }

    // MARK: - Distance geocoding (extracted from AssessmentDataManager)

    /// Geocodes both addresses and returns straight-line miles plus whether the
    /// move crosses state lines. Unknown states count as interstate (matches the
    /// pre-extraction "better to over-prepare" default). Returns nil when either
    /// address is empty or geocoding fails; callers apply their own fallbacks.
    func geocodedDistance(
        from currentAddress: String, to newAddress: String
    ) async -> (miles: Double, isInterstate: Bool)? {
        guard !currentAddress.isEmpty, !newAddress.isEmpty else { return nil }
        let geocoder = CLGeocoder()

        do {
            // CLGeocoder requires sequential calls (shared internal state)
            let fromPlacemarks = try await geocoder.geocodeAddressString(currentAddress)
            let toPlacemarks = try await geocoder.geocodeAddressString(newAddress)

            guard let fromPlacemark = fromPlacemarks.first,
                  let toPlacemark = toPlacemarks.first,
                  let fromLocation = fromPlacemark.location,
                  let toLocation = toPlacemark.location else { return nil }

            let miles = fromLocation.distance(from: toLocation) / 1609.34

            let fromState = fromPlacemark.administrativeArea ?? ""
            let toState = toPlacemark.administrativeArea ?? ""
            let isInterstate = fromState.isEmpty || toState.isEmpty
                ? true
                : fromState.lowercased() != toState.lowercased()

            return (miles, isInterstate)
        } catch {
            #if DEBUG
            print("⚠️ Geocoding failed: \(error.localizedDescription)")
            #endif
            return nil
        }
    }
}
