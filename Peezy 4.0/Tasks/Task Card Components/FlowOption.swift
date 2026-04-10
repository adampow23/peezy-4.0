//
//  FlowOption.swift
//  Peezy 4.0
//
//  Created by Adam Powell on 4/10/26.
//

import Foundation

// MARK: - Flow Option
// Simple data type for task flow card options.
// No dependency on TileOption, QuestionOption, or any existing model.

struct FlowOption: Identifiable, Equatable {
    let id: String
    let label: String
    let icon: String
    var subtitle: String? = nil
    var isExclusive: Bool = false
    var fillPercent: Double? = nil
}
