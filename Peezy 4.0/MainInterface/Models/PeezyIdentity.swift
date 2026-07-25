//
//  PeezyIdentity.swift
//  Peezy 4.0
//
//  Single authoritative identity model, persisted at users/{uid}/identity/identity
//  (the "identity doc"). Written at assessment completion, migrated for existing
//  users on launch, edited from Settings. peezy-v1-architecture.md §4 is the contract.
//

import Foundation
import FirebaseFirestore

// MARK: - PeezyAddress

struct PeezyAddress: Codable, Equatable {
    var street: String
    var unit: String?
    var city: String
    var state: String
    var zip: String
    /// The original AddressSearchManager string, preserved verbatim for
    /// geocoding and as the fallback display when parsing fails.
    var raw: String

    /// Single-line display: "170 Main St, Los Altos, CA 94022" (unit appended
    /// to the street when present). Falls back to `raw` when parsing produced
    /// no components.
    var displayLine: String {
        guard !street.isEmpty || !city.isEmpty || !state.isEmpty else { return raw }
        var streetPart = street
        if let unit, !unit.isEmpty { streetPart += " \(unit)" }
        let statePart = [state, zip].filter { !$0.isEmpty }.joined(separator: " ")
        return [streetPart, city, statePart].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// Parses the two comma-separated US formats the assessment stores
    /// (canonical AddressSearchManager output "170 Main St, Los Altos, CA, 94022"
    /// and the completer fallback "170 Main St, Los Altos, CA 94022, United States").
    /// Ported from the UserState city/state parser (commit 8413f2d), extended to
    /// retain the street component, zip, and raw string. The state is the last
    /// two-letter uppercase token optionally followed by a zip; the city is the
    /// component before it; the street is everything before the city.
    static func parse(addressString: String) -> PeezyAddress {
        let parts = addressString
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }

        for (index, part) in parts.enumerated().reversed() {
            let tokens = part.split(separator: " ")
            guard let state = tokens.first,
                  state.count == 2,
                  state.allSatisfy({ $0.isLetter && $0.isUppercase }),
                  tokens.dropFirst().allSatisfy({ token in
                      token.allSatisfy { $0.isNumber || $0 == "-" }
                  })
            else { continue }

            var zip = tokens.dropFirst().joined(separator: "-")
            if zip.isEmpty, index + 1 < parts.count {
                let next = parts[index + 1]
                if !next.isEmpty, next.allSatisfy({ $0.isNumber || $0 == "-" }) {
                    zip = next
                }
            }
            let city = index > 0 ? parts[index - 1] : ""
            let street = parts.prefix(max(index - 1, 0)).joined(separator: ", ")
            return PeezyAddress(
                street: street, unit: nil, city: city, state: String(state),
                zip: zip, raw: addressString
            )
        }
        return PeezyAddress(
            street: parts.first ?? "", unit: nil, city: "", state: "",
            zip: "", raw: addressString
        )
    }

    // MARK: Firestore encoding (manual, matching the codebase's dict idiom)

    func toFirestoreData() -> [String: Any] {
        var data: [String: Any] = [
            "street": street, "city": city, "state": state, "zip": zip, "raw": raw
        ]
        if let unit { data["unit"] = unit }
        return data
    }

    init(street: String, unit: String?, city: String, state: String, zip: String, raw: String) {
        self.street = street
        self.unit = unit
        self.city = city
        self.state = state
        self.zip = zip
        self.raw = raw
    }

    init?(firestoreData: [String: Any]) {
        guard let raw = firestoreData["raw"] as? String else { return nil }
        self.street = firestoreData["street"] as? String ?? ""
        self.unit = firestoreData["unit"] as? String
        self.city = firestoreData["city"] as? String ?? ""
        self.state = firestoreData["state"] as? String ?? ""
        self.zip = firestoreData["zip"] as? String ?? ""
        self.raw = raw
    }
}

// MARK: - PeezyIdentity

struct PeezyIdentity: Codable, Equatable {
    var name: String
    var email: String
    /// Collected in the first vendor booking (Spec 04), not the assessment.
    var phone: String?
    var currentAddress: PeezyAddress?
    var newAddress: PeezyAddress?
    var moveDate: Date?
    var moveDistanceMiles: Double?
    var isInterstate: Bool?
    /// Escape-hatch flags (Spec 02 Phase B): the user completed the
    /// assessment without a final new address / with a best-guess date.
    var newAddressPending: Bool? = nil
    var moveDatePending: Bool? = nil

    // MARK: Firestore encoding

    func toFirestoreData() -> [String: Any] {
        var data: [String: Any] = ["name": name, "email": email]
        if let phone { data["phone"] = phone }
        if let currentAddress { data["currentAddress"] = currentAddress.toFirestoreData() }
        if let newAddress { data["newAddress"] = newAddress.toFirestoreData() }
        if let moveDate { data["moveDate"] = Timestamp(date: moveDate) }
        if let moveDistanceMiles { data["moveDistanceMiles"] = moveDistanceMiles }
        if let isInterstate { data["isInterstate"] = isInterstate }
        if let newAddressPending { data["newAddressPending"] = newAddressPending }
        if let moveDatePending { data["moveDatePending"] = moveDatePending }
        return data
    }

    init(
        name: String, email: String, phone: String? = nil,
        currentAddress: PeezyAddress? = nil, newAddress: PeezyAddress? = nil,
        moveDate: Date? = nil, moveDistanceMiles: Double? = nil, isInterstate: Bool? = nil
    ) {
        self.name = name
        self.email = email
        self.phone = phone
        self.currentAddress = currentAddress
        self.newAddress = newAddress
        self.moveDate = moveDate
        self.moveDistanceMiles = moveDistanceMiles
        self.isInterstate = isInterstate
    }

    init(firestoreData: [String: Any]) {
        self.name = firestoreData["name"] as? String ?? ""
        self.email = firestoreData["email"] as? String ?? ""
        self.phone = firestoreData["phone"] as? String
        self.currentAddress = (firestoreData["currentAddress"] as? [String: Any])
            .flatMap(PeezyAddress.init(firestoreData:))
        self.newAddress = (firestoreData["newAddress"] as? [String: Any])
            .flatMap(PeezyAddress.init(firestoreData:))
        if let timestamp = firestoreData["moveDate"] as? Timestamp {
            self.moveDate = timestamp.dateValue()
        }
        self.moveDistanceMiles = (firestoreData["moveDistanceMiles"] as? NSNumber)?.doubleValue
        self.isInterstate = firestoreData["isInterstate"] as? Bool
        self.newAddressPending = firestoreData["newAddressPending"] as? Bool
        self.moveDatePending = firestoreData["moveDatePending"] as? Bool
    }
}
