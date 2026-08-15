//
//  MoversFlowStage.swift
//  Peezy 4.0
//

import Foundation

enum MoversFlowStage: Int, Equatable {
    case loading
    case preparation
    case quotes
    case matrix
    /// Terminal chain state (plan v7): the edge's spawn + completion writes
    /// are durable; Done is the only way out and performs no writes.
    case confirmation
    case failure

    var persistedTaskStage: TaskStage? {
        switch self {
        case .quotes:
            .compare
        case .matrix:
            .verify
        case .loading, .preparation, .confirmation, .failure:
            nil
        }
    }
}

struct MoversPreparationPage: Equatable {
    enum Kind: Equatable {
        case education
        case intro
        case callSheetSection(items: [String])
    }

    enum PrimaryAction: Equatable {
        case advance
        case getQuotes
    }

    let kind: Kind
    let title: String
    let body: String?
    let systemImage: String
    let accessibilityPrefix: String
    let primary: PrimaryAction
}
