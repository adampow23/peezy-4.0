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


// MARK: ═══════════════════════════════════════════════════════════
// MARK: PREVIEWS
// MARK: ═══════════════════════════════════════════════════════════

#if DEBUG

// MARK: Single-Select Previews

#Preview("SS-2 · Update or Cancel") {
    TaskFlowSelect2Card(
        taskTitle: "Handle my gym membership",
        question: "What would you like to do?",
        option1: FlowOption(id: "update", label: "Update my address", icon: "pencil.line"),
        option2: FlowOption(id: "cancel", label: "Cancel membership", icon: "xmark.circle"),
        selectedIds: [],
        showBack: true,
        onSelect: { _ in },
        onBack: { }
    )
    .peezyCardChrome()
}

#Preview("SS-3 · Removal Route") {
    TaskFlowSelect3Card(
        taskTitle: "Schedule donation pickup",
        question: "What are you looking to do with these items?",
        option1: FlowOption(id: "donate", label: "Donate them", icon: "heart"),
        option2: FlowOption(id: "haul_away", label: "Have them hauled away", icon: "truck.box"),
        option3: FlowOption(id: "not_sure", label: "Not sure — help me decide", icon: "questionmark.circle"),
        selectedIds: [],
        showBack: true,
        onSelect: { _ in },
        onBack: { }
    )
    .peezyCardChrome()
}

#Preview("SS-4 · Contract Preference") {
    TaskFlowSelect4Card(
        taskTitle: "Set up your internet",
        question: "Contract preference?",
        option1: FlowOption(id: "month_to_month", label: "Month-to-month", icon: "calendar"),
        option2: FlowOption(id: "1_year", label: "1 year", icon: "calendar.badge.clock"),
        option3: FlowOption(id: "2_year", label: "2 year", icon: "calendar.badge.checkmark"),
        option4: FlowOption(id: "no_preference", label: "No preference", icon: "hand.thumbsup"),
        selectedIds: [],
        showBack: true,
        onSelect: { _ in },
        onBack: { }
    )
    .peezyCardChrome()
}

#Preview("SS-5 · Insurance Provider") {
    TaskFlowSelect5Card(
        taskTitle: "Update your auto insurance",
        question: "Who is your current provider?",
        option1: FlowOption(id: "state_farm", label: "State Farm", icon: "shield.fill"),
        option2: FlowOption(id: "geico", label: "GEICO", icon: "shield.fill"),
        option3: FlowOption(id: "progressive", label: "Progressive", icon: "shield.fill"),
        option4: FlowOption(id: "allstate", label: "Allstate", icon: "shield.fill"),
        option5: FlowOption(id: "other", label: "Other", icon: "ellipsis.circle"),
        selectedIds: [],
        showBack: true,
        onSelect: { _ in },
        onBack: { }
    )
    .peezyCardChrome()
}

// MARK: Multi-Select Previews

#Preview("MS-3 · Delicate Items") {
    TaskFlowMulti3Card(
        taskTitle: "Book your movers",
        question: "Any items needing extra care?",
        option1: FlowOption(id: "art", label: "Art / Antiques", icon: "photo.artframe"),
        option2: FlowOption(id: "glass", label: "Large Mirrors / Glass", icon: "rectangle"),
        option3: FlowOption(id: "china", label: "China / Dishware", icon: "wineglass"),
        selectedIds: ["art"],
        showBack: true,
        onSelect: { _ in },
        onContinue: { },
        onBack: { }
    )
    .peezyCardChrome()
}

#Preview("MS-4 · Cleaning Services") {
    TaskFlowMulti4Card(
        taskTitle: "Book your cleaners",
        question: "What services do you need?",
        option1: FlowOption(id: "standard", label: "Standard clean", icon: "sparkles"),
        option2: FlowOption(id: "deep", label: "Deep clean", icon: "bubbles.and.sparkles"),
        option3: FlowOption(id: "carpet", label: "Carpet cleaning", icon: "square.grid.3x3.topleft.filled"),
        option4: FlowOption(id: "windows", label: "Window cleaning", icon: "window.horizontal"),
        selectedIds: ["standard", "carpet"],
        showBack: true,
        onSelect: { _ in },
        onContinue: { },
        onBack: { }
    )
    .peezyCardChrome()
}

#Preview("MS-5 · Internet Usage") {
    TaskFlowMulti5Card(
        taskTitle: "Set up your internet",
        question: "Who's using the internet?",
        option1: FlowOption(id: "wfh", label: "Work from home", icon: "laptopcomputer"),
        option2: FlowOption(id: "streaming", label: "Streaming", icon: "play.tv.fill"),
        option3: FlowOption(id: "gaming", label: "Gaming", icon: "gamecontroller.fill"),
        option4: FlowOption(id: "smart_home", label: "Smart home devices", icon: "homekit"),
        option5: FlowOption(id: "basic", label: "Just browsing and email", icon: "globe"),
        selectedIds: ["wfh", "streaming"],
        showBack: true,
        onSelect: { _ in },
        onContinue: { },
        onBack: { }
    )
    .peezyCardChrome()
}

#Preview("MS-6 · Item Categories") {
    TaskFlowMulti6Card(
        taskTitle: "Schedule donation pickup",
        question: "What types of items?",
        option1: FlowOption(id: "furniture", label: "Furniture", icon: "sofa"),
        option2: FlowOption(id: "appliances", label: "Appliances", icon: "refrigerator"),
        option3: FlowOption(id: "electronics", label: "Electronics", icon: "desktopcomputer"),
        option4: FlowOption(id: "mattresses", label: "Mattresses", icon: "bed.double"),
        option5: FlowOption(id: "household", label: "Household / clothing", icon: "house"),
        option6: FlowOption(id: "outdoor", label: "Outdoor / debris", icon: "leaf"),
        selectedIds: ["furniture", "electronics", "outdoor"],
        showBack: true,
        onSelect: { _ in },
        onContinue: { },
        onBack: { }
    )
    .peezyCardChrome()
}

#endif
