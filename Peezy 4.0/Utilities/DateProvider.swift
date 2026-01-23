import Foundation

/// Provides the current date, with override capability for testing.
/// Usage: Replace Date() with DateProvider.shared.now in business logic.
final class DateProvider {

    // MARK: - Singleton

    static let shared = DateProvider()
    private init() {}

    // MARK: - Properties

    #if DEBUG
    /// When set, this date is returned instead of the actual current date.
    /// Only available in DEBUG builds.
    var simulatedDate: Date?
    #endif

    /// Returns the current date, or the simulated date if set (DEBUG only).
    var now: Date {
        #if DEBUG
        return simulatedDate ?? Date()
        #else
        return Date()
        #endif
    }

    // MARK: - Debug Controls

    #if DEBUG
    /// Advances the simulated date by one day.
    func advanceOneDay() {
        let current = simulatedDate ?? Date()
        simulatedDate = Calendar.current.date(byAdding: .day, value: 1, to: current)
    }

    /// Moves the simulated date back by one day.
    func goBackOneDay() {
        let current = simulatedDate ?? Date()
        simulatedDate = Calendar.current.date(byAdding: .day, value: -1, to: current)
    }

    /// Sets the simulated date to a specific number of days before a target date.
    /// - Parameters:
    ///   - daysUntil: Number of days until the target date (0 = target date itself)
    ///   - targetDate: The reference date (e.g., move date)
    func setDaysUntil(_ daysUntil: Int, before targetDate: Date) {
        simulatedDate = Calendar.current.date(byAdding: .day, value: -daysUntil, to: targetDate)
    }

    /// Resets to using the real current date.
    func resetToRealTime() {
        simulatedDate = nil
    }

    /// Whether we're currently using a simulated date.
    var isSimulating: Bool {
        simulatedDate != nil
    }
    #endif
}
