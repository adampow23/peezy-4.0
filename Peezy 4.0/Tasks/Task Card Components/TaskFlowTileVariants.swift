//
//  TaskFlowTileVariants.swift
//  Peezy 4.0
//
//  Created by Adam Powell on 4/12/26.
//

import SwiftUI

// MARK: ═══════════════════════════════════════════════════════════
// MARK: SINGLE-SELECT VARIANTS (tap → auto-advance, no button)
// MARK: ═══════════════════════════════════════════════════════════

// MARK: - Single-Select 2 Options
// Max label: 32 characters. Icon + label only, no subtitles.
// Used for: action choice (update/cancel, update/transfer, one-way/round-trip)
// Same vertical tile layout as all other select cards — NOT side-by-side.

struct TaskFlowSelect2Card: View {
    let taskTitle: String
    let question: String
    let option1: FlowOption
    let option2: FlowOption
    let selectedIds: Set<String>
    var showBack: Bool = false
    let onSelect: (String) -> Void
    var onBack: (() -> Void)? = nil

    var body: some View {
        TaskFlowTilesCard(
            taskTitle: taskTitle,
            question: question,
            options: [option1, option2],
            mode: .single,
            selectedIds: selectedIds,
            showBack: showBack,
            onSelect: onSelect,
            onBack: onBack
        )
    }
}

// MARK: - Single-Select 3 Options
// Max label: 30 characters. Icon + label only, no subtitles.
// Used for: removal route, which place, pickup preference, people count,
//           storage size, trip type, care type

struct TaskFlowSelect3Card: View {
    let taskTitle: String
    let question: String
    let option1: FlowOption
    let option2: FlowOption
    let option3: FlowOption
    let selectedIds: Set<String>
    var showBack: Bool = false
    let onSelect: (String) -> Void
    var onBack: (() -> Void)? = nil

    var body: some View {
        TaskFlowTilesCard(
            taskTitle: taskTitle,
            question: question,
            options: [option1, option2, option3],
            mode: .single,
            selectedIds: selectedIds,
            showBack: showBack,
            onSelect: onSelect,
            onBack: onBack
        )
    }
}

// MARK: - Single-Select 4 Options
// Max label: 28 characters. Icon + label only, no subtitles.
// Used for: timing, contract preference, item condition, quantity,
//           item location, estimated value, manage provider actions (4-option)

struct TaskFlowSelect4Card: View {
    let taskTitle: String
    let question: String
    let option1: FlowOption
    let option2: FlowOption
    let option3: FlowOption
    let option4: FlowOption
    let selectedIds: Set<String>
    var showBack: Bool = false
    let onSelect: (String) -> Void
    var onBack: (() -> Void)? = nil

    var body: some View {
        TaskFlowTilesCard(
            taskTitle: taskTitle,
            question: question,
            options: [option1, option2, option3, option4],
            mode: .single,
            selectedIds: selectedIds,
            showBack: showBack,
            onSelect: onSelect,
            onBack: onBack
        )
    }
}

// MARK: - Single-Select 5 Options
// Max label: 24 characters. Icon + label only, no subtitles.
// Used for: insurance providers

struct TaskFlowSelect5Card: View {
    let taskTitle: String
    let question: String
    let option1: FlowOption
    let option2: FlowOption
    let option3: FlowOption
    let option4: FlowOption
    let option5: FlowOption
    let selectedIds: Set<String>
    var showBack: Bool = false
    let onSelect: (String) -> Void
    var onBack: (() -> Void)? = nil

    var body: some View {
        TaskFlowTilesCard(
            taskTitle: taskTitle,
            question: question,
            options: [option1, option2, option3, option4, option5],
            mode: .single,
            selectedIds: selectedIds,
            showBack: showBack,
            onSelect: onSelect,
            onBack: onBack
        )
    }
}


// MARK: ═══════════════════════════════════════════════════════════
// MARK: MULTI-SELECT VARIANTS (toggle + Continue button at bottom)
// MARK: ═══════════════════════════════════════════════════════════

// MARK: - Multi-Select 3 Options
// Max label: 28 characters. Icon + label only, no subtitles.
// Used for: delicate items

struct TaskFlowMulti3Card: View {
    let taskTitle: String
    let question: String
    let option1: FlowOption
    let option2: FlowOption
    let option3: FlowOption
    let selectedIds: Set<String>
    var showBack: Bool = false
    let onSelect: (String) -> Void
    let onContinue: () -> Void
    var onBack: (() -> Void)? = nil

    var body: some View {
        TaskFlowTilesCard(
            taskTitle: taskTitle,
            question: question,
            options: [option1, option2, option3],
            mode: .multi,
            selectedIds: selectedIds,
            showBack: showBack,
            onSelect: onSelect,
            onContinue: onContinue,
            onBack: onBack
        )
    }
}

// MARK: - Multi-Select 4 Options
// Max label: 28 characters. Icon + label only, no subtitles.
// Used for: heavy items, cleaning services

struct TaskFlowMulti4Card: View {
    let taskTitle: String
    let question: String
    let option1: FlowOption
    let option2: FlowOption
    let option3: FlowOption
    let option4: FlowOption
    let selectedIds: Set<String>
    var showBack: Bool = false
    let onSelect: (String) -> Void
    let onContinue: () -> Void
    var onBack: (() -> Void)? = nil

    var body: some View {
        TaskFlowTilesCard(
            taskTitle: taskTitle,
            question: question,
            options: [option1, option2, option3, option4],
            mode: .multi,
            selectedIds: selectedIds,
            showBack: showBack,
            onSelect: onSelect,
            onContinue: onContinue,
            onBack: onBack
        )
    }
}

// MARK: - Multi-Select 5 Options
// Max label: 24 characters. Icon + label only, no subtitles.
// Used for: internet usage, platforms, sell categories

struct TaskFlowMulti5Card: View {
    let taskTitle: String
    let question: String
    let option1: FlowOption
    let option2: FlowOption
    let option3: FlowOption
    let option4: FlowOption
    let option5: FlowOption
    let selectedIds: Set<String>
    var showBack: Bool = false
    let onSelect: (String) -> Void
    let onContinue: () -> Void
    var onBack: (() -> Void)? = nil

    var body: some View {
        TaskFlowTilesCard(
            taskTitle: taskTitle,
            question: question,
            options: [option1, option2, option3, option4, option5],
            mode: .multi,
            selectedIds: selectedIds,
            showBack: showBack,
            onSelect: onSelect,
            onContinue: onContinue,
            onBack: onBack
        )
    }
}

// MARK: - Multi-Select 6 Options
// Max label: 24 characters. Icon + label only, no subtitles.
// Used for: remove item categories

struct TaskFlowMulti6Card: View {
    let taskTitle: String
    let question: String
    let option1: FlowOption
    let option2: FlowOption
    let option3: FlowOption
    let option4: FlowOption
    let option5: FlowOption
    let option6: FlowOption
    let selectedIds: Set<String>
    var showBack: Bool = false
    let onSelect: (String) -> Void
    let onContinue: () -> Void
    var onBack: (() -> Void)? = nil

    var body: some View {
        TaskFlowTilesCard(
            taskTitle: taskTitle,
            question: question,
            options: [option1, option2, option3, option4, option5, option6],
            mode: .multi,
            selectedIds: selectedIds,
            showBack: showBack,
            onSelect: onSelect,
            onContinue: onContinue,
            onBack: onBack
        )
    }
}
