//
//  TimeOfDay.swift
//  Peezy
//
//  Time-of-day enum used for greetings, empty-state styling,
//  and background color theming across the app.
//

import SwiftUI

enum TimeOfDay {
    case morning    // 5..<12
    case afternoon  // 12..<17
    case evening    // 17..<22
    case night      // 22... or ..<5

    /// Returns the case matching the current hour.
    static var current: TimeOfDay {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return .morning
        case 12..<17: return .afternoon
        case 17..<22: return .evening
        default:      return .night
        }
    }

    // MARK: - Greeting

    var greeting: String {
        switch self {
        case .morning:   return "Good morning"
        case .afternoon: return "Good afternoon"
        case .evening:   return "Good evening"
        case .night:     return "Hey"
        }
    }

    // MARK: - Empty State

    var emptyStateHeadline: String {
        switch self {
        case .morning:   return "Fresh start"
        case .afternoon: return "All clear"
        case .evening:   return "You're done"
        case .night:     return "All caught up"
        }
    }

    @ViewBuilder
    var emptyStateIconStyle: some View {
        switch self {
        case .morning:
            Image(systemName: "sun.max.fill")
                .foregroundStyle(.yellow)
        case .afternoon:
            Image(systemName: "sun.min.fill")
                .foregroundStyle(.orange)
        case .evening:
            Image(systemName: "moon.fill")
                .foregroundStyle(.indigo)
        case .night:
            Image(systemName: "moon.stars.fill")
                .foregroundStyle(.purple)
        }
    }

    // MARK: - Background Theme

    /// Deep background color for InteractiveBackground.
    var baseColor: Color {
        switch self {
        case .morning:   return Color(red: 0.08, green: 0.08, blue: 0.12)
        case .afternoon: return Color(red: 0.10, green: 0.08, blue: 0.14)
        case .evening:   return Color(red: 0.06, green: 0.05, blue: 0.12)
        case .night:     return Color(red: 0.04, green: 0.03, blue: 0.08)
        }
    }

    /// Animated orb gradient colors for InteractiveBackground.
    var orbColors: (primary: Color, secondary: Color, accent: Color) {
        switch self {
        case .morning:
            return (.blue, .cyan, .teal)
        case .afternoon:
            return (.indigo, .purple, .blue)
        case .evening:
            return (.purple, .indigo, .blue)
        case .night:
            return (.indigo, Color(red: 0.2, green: 0.1, blue: 0.4), .purple)
        }
    }
}
