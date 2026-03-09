//
//  KeyboardObserver.swift
//  Peezy
//
//  Lightweight keyboard height tracker for keyboard-aware layouts.
//  Usage: @StateObject private var keyboard = KeyboardObserver()
//

import SwiftUI
import Combine

final class KeyboardObserver: ObservableObject {
    @Published var height: CGFloat = 0

    var isVisible: Bool { height > 0 }

    private var cancellables = Set<AnyCancellable>()

    init() {
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            .compactMap { ($0.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect)?.height }
            .sink { [weak self] height in
                withAnimation(.easeOut(duration: 0.25)) {
                    self?.height = height
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            .sink { [weak self] _ in
                withAnimation(.easeOut(duration: 0.25)) {
                    self?.height = 0
                }
            }
            .store(in: &cancellables)
    }
}
