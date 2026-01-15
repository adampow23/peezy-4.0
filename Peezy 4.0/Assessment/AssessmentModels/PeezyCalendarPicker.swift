//
//  PeezyCalendarPicker.swift
//  PeezyV1.0
//
//  Shared calendar styling for date selection with Peezy glass look.
//

import SwiftUI

// MARK: - Day Model

struct Day: Identifiable {
    let id = UUID()
    let date: Date
    let ignored: Bool  // For days outside the current month

    init(date: Date, ignored: Bool = false) {
        self.date = date
        self.ignored = ignored
    }
}

// MARK: - Calendar Day Cell

struct CalendarDayCell: View {
    let day: Day
    let isSelected: Bool
    let isToday: Bool
    let taskCount: Int
    let progress: Double

    private var calendar: Calendar { Calendar.current }

    var body: some View {
        ZStack {
            // Background
            if isSelected {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(PeezyTheme.Colors.brandYellow)
            } else if isToday {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(PeezyTheme.Colors.brandYellow, lineWidth: 2)
            }

            // Day number
            Text("\(calendar.component(.day, from: day.date))")
                .font(.system(size: 16, weight: isSelected ? .semibold : .regular))
                .foregroundColor(dayTextColor)
        }
        .frame(height: 40)
    }

    private var dayTextColor: Color {
        if day.ignored {
            return .clear
        } else if isSelected {
            return .black
        } else {
            return .primary
        }
    }
}

// MARK: - Extract Dates Helper

private func extractDates(_ month: Date) -> [Day] {
    let calendar = Calendar.current

    guard let monthInterval = calendar.dateInterval(of: .month, for: month),
          let monthFirstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start),
          let monthLastWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.end - 1)
    else {
        return []
    }

    let dateInterval = DateInterval(start: monthFirstWeek.start, end: monthLastWeek.end)

    var days: [Day] = []
    var current = dateInterval.start

    while current < dateInterval.end {
        let isInMonth = calendar.isDate(current, equalTo: month, toGranularity: .month)
        days.append(Day(date: current, ignored: !isInMonth))
        current = calendar.date(byAdding: .day, value: 1, to: current) ?? current
    }

    return days
}

// MARK: - Peezy Calendar Picker

struct PeezyCalendarPicker: View {
    @Binding var selectedDate: Date
    var minimumDate: Date = .distantPast
    var accentColor: Color = PeezyTheme.Colors.brandYellow

    @State private var currentMonth: Date

    private var calendar: Calendar { Calendar.current }
    private var monthFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }

    private var monthDates: [Day] {
        extractDates(currentMonth)
    }

    private var startOfMinimum: Date {
        calendar.startOfDay(for: minimumDate)
    }

    init(selectedDate: Binding<Date>, minimumDate: Date = .distantPast, accentColor: Color = PeezyTheme.Colors.brandYellow) {
        _selectedDate = selectedDate
        self.minimumDate = minimumDate
        self.accentColor = accentColor

        let monthStart = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: selectedDate.wrappedValue)) ?? Date()
        _currentMonth = State(initialValue: monthStart)
    }

    var body: some View {
        VStack(spacing: 12) {
            header
            weekHeaders
            monthGrid
        }
        .padding(PeezyTheme.Layout.cardPadding)
        .peezyGlassBackground(cornerRadius: PeezyTheme.Layout.cornerRadius)
        .peezyCardShadow()
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(monthFormatter.string(from: currentMonth))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.primary)
            }

            Spacer()

            HStack(spacing: 12) {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                        stepMonth(forward: false)
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 36, height: 36)
                        .background(Color(UIColor.systemGray6))
                        .clipShape(Circle())
                }
                .disabled(!canMoveToPreviousMonth)
                .opacity(canMoveToPreviousMonth ? 1 : 0.35)

                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                        stepMonth(forward: true)
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 36, height: 36)
                        .background(Color(UIColor.systemGray6))
                        .clipShape(Circle())
                }
            }
        }
    }

    private var weekHeaders: some View {
        HStack(spacing: 0) {
            ForEach(Calendar.current.veryShortWeekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
            }
        }
        .padding(.vertical, 4)
    }

    private var monthGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(spacing: 6), count: 7), spacing: 8) {
            ForEach(monthDates) { day in
                let isSelected = calendar.isDate(day.date, inSameDayAs: selectedDate)
                let isToday = calendar.isDateInToday(day.date)
                let isBeforeMinimum = calendar.startOfDay(for: day.date) < startOfMinimum
                let isDisabled = isBeforeMinimum || day.ignored

                CalendarDayCell(
                    day: day,
                    isSelected: isSelected,
                    isToday: isToday,
                    taskCount: 0,
                    progress: 0
                )
                .overlay(alignment: .bottomTrailing) {
                    if isSelected {
                        Circle()
                            .fill(accentColor)
                            .frame(width: 6, height: 6)
                            .offset(x: -6, y: -6)
                    }
                }
                .opacity(isDisabled ? 0.32 : 1.0)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !isDisabled else { return }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedDate = day.date
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private var canMoveToPreviousMonth: Bool {
        guard let minMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: startOfMinimum)) else {
            return true
        }
        return currentMonth > minMonth
    }

    private func stepMonth(forward: Bool) {
        guard let newMonth = calendar.date(byAdding: .month, value: forward ? 1 : -1, to: currentMonth) else { return }

        if !forward && !canMoveToPreviousMonth { return }

        currentMonth = newMonth

        // Auto-select a valid date when paging months
        if calendar.isDate(selectedDate, equalTo: currentMonth, toGranularity: .month) == false {
            if let firstValid = monthDates.first(where: { !$0.ignored && calendar.startOfDay(for: $0.date) >= startOfMinimum }) {
                selectedDate = firstValid.date
            }
        }
    }
}

#Preview {
    @Previewable @State var date = Date()
    PeezyCalendarPicker(selectedDate: $date, minimumDate: Date())
        .padding()
        .background(Color(.systemBackground))
}
