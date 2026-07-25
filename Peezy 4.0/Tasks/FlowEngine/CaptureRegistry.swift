//
//  CaptureRegistry.swift
//  Peezy 4.0
//
//  Capture-modality registry (Spec 04 Phase C — the shim; capture
//  parameterization proper lands in Spec 05). Replaces ScanInventoryFlow's
//  bespoke special-casing as the LOOKUP: TasksStore/TaskRowButtons keep
//  consulting PeezyCard.isScanInventory, which now resolves here — the 8th
//  vertical attaches by adding a registration, not by touching TasksStore.
//

import Foundation

/// Capture modalities. `roomScan` is reserved for the LiDAR wave (Spec 05+).
enum CaptureKind: String {
    case videoInventory
    case roomScan
}

struct CaptureRegistration {
    let kind: CaptureKind
    /// Catalog taskId whose card opens this capture path.
    let taskId: String
    /// Router flow id (workflowId or lowercased taskId).
    let flowId: String
    /// Whether the Tasks tab offers the destructive reset action
    /// (video inventory's "Reset inventory").
    let supportsReset: Bool
}

enum CaptureRegistry {

    static let registrations: [CaptureRegistration] = [
        CaptureRegistration(
            kind: .videoInventory,
            taskId: "SCAN_INVENTORY",
            flowId: "scan_inventory",
            supportsReset: true
        )
    ]

    static func registration(taskId: String?) -> CaptureRegistration? {
        guard let taskId else { return nil }
        return registrations.first { $0.taskId == taskId }
    }

    static func registration(flowId: String) -> CaptureRegistration? {
        registrations.first { $0.flowId == flowId }
    }
}
