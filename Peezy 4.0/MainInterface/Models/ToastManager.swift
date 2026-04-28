//
//  ToastManager.swift
//  Peezy 4.0
//
//  Global queued toast notification state.
//

import SwiftUI
import Observation
import UIKit

@Observable
final class ToastManager {
    static let shared = ToastManager()

    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let message: String
        let style: Style
        let createdAt = Date()

        static func == (lhs: Toast, rhs: Toast) -> Bool {
            lhs.id == rhs.id
        }
    }

    enum Style {
        case standard
        case success
        case error
        case warning
    }

    private(set) var currentToast: Toast?
    private var queue: [Toast] = []
    private var lastShownMessages: [(message: String, timestamp: Date)] = []
    private var dismissTask: Task<Void, Never>?

    private let displayDuration: TimeInterval = 2.5
    private let dedupWindow: TimeInterval = 3.0

    private init() {}

    /// Show a toast. Duplicate messages fired within 3 seconds are ignored.
    @MainActor
    func show(_ message: String, style: Style = .standard) {
        let now = Date()
        lastShownMessages.removeAll { now.timeIntervalSince($0.timestamp) > dedupWindow }

        if lastShownMessages.contains(where: { $0.message == message }) {
            return
        }

        lastShownMessages.append((message: message, timestamp: now))

        let toast = Toast(message: message, style: style)

        if currentToast == nil {
            currentToast = toast
            announce(toast)
            scheduleDismissal()
        } else {
            queue.append(toast)
        }
    }

    /// Dismiss current toast early, such as when the user taps it.
    @MainActor
    func dismissCurrent() {
        dismissTask?.cancel()
        advance()
    }

    @MainActor
    private func scheduleDismissal() {
        dismissTask?.cancel()

        let duration = displayDuration
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }

            await MainActor.run {
                self?.advance()
            }
        }
    }

    @MainActor
    private func advance() {
        if queue.isEmpty {
            currentToast = nil
        } else {
            let nextToast = queue.removeFirst()
            currentToast = nextToast
            announce(nextToast)
            scheduleDismissal()
        }
    }

    @MainActor
    private func announce(_ toast: Toast) {
        UIAccessibility.post(notification: .announcement, argument: toast.message)
    }
}
