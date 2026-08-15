//
//  MoversFlowStage.swift
//  Peezy 4.0
//

import Foundation

enum MoversFlowStage: Int, Equatable {
    case loading
    case protectionEducation
    case estimateEducation
    case equip
    case quotes
    case matrix
    /// Terminal chain state (plan v7): the edge's spawn + completion writes
    /// are durable; Done is the only way out and performs no writes.
    case confirmation
    case failure

    var stackIndex: Int {
        switch self {
        case .loading, .protectionEducation, .failure: 0
        case .estimateEducation: 1
        case .equip: 2
        case .quotes: 3
        case .matrix, .confirmation: 4
        }
    }

    var cardsRemaining: Int {
        max(5 - stackIndex, 1)
    }

    var persistedTaskStage: TaskStage? {
        switch self {
        case .quotes:
            .compare
        case .matrix:
            .verify
        case .loading, .protectionEducation, .estimateEducation, .equip, .confirmation, .failure:
            nil
        }
    }
}
