//
//  MoversFlowStage.swift
//  Peezy 4.0
//

import Foundation

enum MoversFlowStage: Int, Equatable {
    case loading
    case capture
    case scope
    case refinement
    case comparison
    case booking
    case confirmation
    case failure

    var stackIndex: Int {
        switch self {
        case .loading: 0
        case .capture: 1
        case .scope: 2
        case .refinement: 3
        case .comparison: 4
        case .booking: 5
        case .confirmation: 6
        case .failure: 7
        }
    }

    var cardsRemaining: Int {
        max(7 - stackIndex, 1)
    }

    var persistedTaskStage: TaskStage? {
        switch self {
        case .loading, .failure: nil
        case .capture: .capture
        case .scope, .refinement: .scope
        case .comparison: .compare
        case .booking: .book
        case .confirmation: .verify
        }
    }
}
