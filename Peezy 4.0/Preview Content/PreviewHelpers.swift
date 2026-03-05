//
//  PreviewHelpers.swift
//  Peezy
//
//  Mock data factories for Xcode Previews.
//  All preview code is gated behind #if DEBUG — zero impact on production builds.
//

#if DEBUG
import Foundation
import SwiftUI

// MARK: - Mock Data

enum PreviewData {

    // MARK: - User State

    static var mockUserState: UserState {
        var state = UserState(userId: "preview-user-123", name: "Adam")
        state.moveDate = Calendar.current.date(byAdding: .day, value: 21, to: Date())
        state.moveDistance = .local
        state.originCity = "Brooklyn"
        state.originState = "NY"
        state.destinationCity = "Park Slope"
        state.destinationState = "NY"
        return state
    }

    // MARK: - Task Cards

    static var mockWorkflowTask: PeezyCard {
        PeezyCard(
            id: "preview-workflow-1",
            type: .task,
            title: "Book movers",
            subtitle: "Research and reserve a moving company to handle your relocation.",
            colorName: "orange",
            taskId: "BOOK_MOVERS",
            workflowId: "book_movers",
            priority: .high,
            status: .upcoming,
            taskCategory: "moving",
            urgencyPercentage: 94,
            selfServiceOnly: false
        )
    }

    static var mockSelfServiceTask: PeezyCard {
        PeezyCard(
            id: "preview-self-1",
            type: .task,
            title: "Buy packing supplies",
            subtitle: "Purchase boxes, tape, bubble wrap, and other materials needed to pack safely.",
            colorName: "green",
            taskId: "BUY_PACKING_SUPPLIES",
            priority: .normal,
            status: .upcoming,
            taskCategory: "packing",
            urgencyPercentage: 85,
            selfServiceOnly: true
        )
    }

    static var mockConciergeTask: PeezyCard {
        PeezyCard(
            id: "preview-concierge-1",
            type: .task,
            title: "Cancel utility accounts",
            subtitle: "Schedule shutoffs for electricity, gas, water, and trash at your current address.",
            colorName: "green",
            taskId: "CANCEL_UTILITIES",
            priority: .normal,
            status: .upcoming,
            taskCategory: "utilities",
            urgencyPercentage: 75,
            selfServiceOnly: false
        )
    }

    static var mockTaskQueue: [PeezyCard] {
        [mockWorkflowTask, mockSelfServiceTask, mockConciergeTask]
    }
}

// MARK: - PeezyHomeViewModel Preview Factory

extension PeezyHomeViewModel {
    /// Creates a pre-configured view model for use in #Preview blocks.
    /// Sets state directly — bypasses Firebase and UserDefaults.
    static func preview(
        state: HomeState,
        task: PeezyCard? = nil,
        tasks: [PeezyCard] = PreviewData.mockTaskQueue
    ) -> PeezyHomeViewModel {
        let vm = PeezyHomeViewModel()
        vm.userState = PreviewData.mockUserState
        vm.state = state
        vm.currentTask = task
        vm.allActiveTasks = tasks
        vm.taskQueue = task != nil ? [] : tasks
        return vm
    }
}
#endif
