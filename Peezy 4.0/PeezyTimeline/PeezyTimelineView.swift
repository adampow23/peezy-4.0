import SwiftUI

// MARK: - 1. DATA MODELS
struct PeezyDay: Identifiable {
    var id: String { formatDateKey(date) }
    var date: Date
    var tasks: [PeezyTimelineTask]

    private func formatDateKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

struct PeezyTimelineTask: Identifiable {
    var id: String
    var title: String
    var subtitle: String
    var time: String
    var type: TaskType
    var dueDate: Date?
    var priority: Int

    enum TaskType {
        case active
        case future
        case completed
        case urgent
    }
}

// MARK: - 2. MAIN VIEW
struct PeezyTaskStream: View {
    // External data
    var viewModel: PeezyStackViewModel?
    var userState: UserState?

    // View Properties
    @State private var days: [PeezyDay] = []
    @State private var selectedDate: Date = DateProvider.shared.now
    @State private var isLoading = true
    @Namespace private var namespace

    // Timeline-specific data fetched directly from Firestore
    @State private var timelineTasks: [PeezyCard] = []
    @State private var isLoadingTasks = false

    // Computed: days until move for timeline range
    private var daysUntilMove: Int {
        userState?.daysUntilMove ?? 30
    }

    // Computed: timeline range (today to move date + 7 days buffer)
    private var timelineRange: Int {
        max(daysUntilMove + 7, 14) // At least 2 weeks, up to move date + buffer
    }

    // Init for standalone use (preview/testing)
    init() {
        self.viewModel = nil
        self.userState = nil
    }

    // Init for integrated use
    init(viewModel: PeezyStackViewModel?, userState: UserState?) {
        self.viewModel = viewModel
        self.userState = userState
    }

    var body: some View {
        ZStack {
            // Background
            InteractiveBackground()

            VStack(spacing: 0) {
                // Top Strip (Week Selector)
                HeaderView()
                    .padding(.bottom, 10)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                    .shadow(color: .black.opacity(0.2), radius: 10, y: 5)

                if isLoading {
                    Spacer()
                    ProgressView()
                        .tint(.white)
                    Spacer()
                } else {
                    GeometryReader { geometry in
                        let size = geometry.size

                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVStack(spacing: 15, pinnedViews: [.sectionHeaders]) {
                                ForEach(days) { day in
                                    let isLast = days.last?.id == day.id

                                    Section {
                                        VStack(alignment: .leading, spacing: 15) {
                                            if day.tasks.isEmpty {
                                                EmptyDayRow()
                                            } else {
                                                ForEach(day.tasks) { task in
                                                    TimelineTaskRow(task: task)
                                                }
                                            }
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.leading, 80)
                                        .padding(.top, -70)
                                        .padding(.bottom, 10)
                                        .frame(minHeight: isLast ? size.height - 110 : nil, alignment: .top)

                                    } header: {
                                        DayHeader(date: day.date, moveDate: userState?.moveDate)
                                    }
                                }
                            }
                            .padding(.top, 20)
                        }
                    }
                }
            }
        }
        .edgesIgnoringSafeArea(.bottom)
        .task {
            await loadTasksFromFirestore()
        }
        .onAppear {
            // Initial load from any available data while Firestore loads
            loadDays()
        }
        .onChange(of: timelineTasks.count) { _, _ in
            loadDays()
        }
    }

    // MARK: - Firestore Data Loading

    private func loadTasksFromFirestore() async {
        isLoadingTasks = true
        do {
            let service = TimelineService()
            timelineTasks = try await service.fetchUserTasks()
            print("📅 Timeline: Loaded \(timelineTasks.count) tasks from Firestore")
            // Trigger UI update
            await MainActor.run {
                loadDays()
            }
        } catch {
            print("❌ Timeline: Failed to load tasks from Firestore: \(error)")
            // Fall back to viewModel if available
            timelineTasks = viewModel?.cards.filter { $0.type == .task || $0.type == .vendor } ?? []
        }
        isLoadingTasks = false
    }

    // MARK: - Data Loading

    private func loadDays() {
        isLoading = true

        // Use timeline tasks from Firestore (primary source)
        // Fall back to viewModel only if timelineTasks is empty and we're still loading
        let cards: [PeezyCard]
        if !timelineTasks.isEmpty {
            cards = timelineTasks.filter { $0.type == .task || $0.type == .vendor }
        } else if !isLoadingTasks, let vmCards = viewModel?.cards {
            // Fallback: use viewModel cards if Firestore load failed
            cards = vmCards.filter { $0.type == .task || $0.type == .vendor }
        } else {
            cards = []
        }

        print("📅 Timeline: Loading days with \(cards.count) task cards, timeline range: \(timelineRange) days")

        if cards.isEmpty {
            // No real tasks - generate empty timeline
            days = generateEmptyTimeline()
        } else {
            // Convert real cards to timeline format
            days = convertCardsToTimeline(cards)
        }

        isLoading = false
    }

    // Generate timeline structure with no tasks
    private func generateEmptyTimeline() -> [PeezyDay] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: DateProvider.shared.now)
        var result: [PeezyDay] = []

        for i in 0..<timelineRange {
            if let date = calendar.date(byAdding: .day, value: i, to: today) {
                result.append(PeezyDay(date: date, tasks: []))
            }
        }

        return result
    }

    // Convert PeezyCards to timeline days
    private func convertCardsToTimeline(_ cards: [PeezyCard]) -> [PeezyDay] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: DateProvider.shared.now)

        // Create day buckets for the timeline range
        var dayMap: [String: [PeezyTimelineTask]] = [:]
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        // Initialize all days
        for i in 0..<timelineRange {
            if let date = calendar.date(byAdding: .day, value: i, to: today) {
                let key = dateFormatter.string(from: date)
                dayMap[key] = []
            }
        }

        // Map cards to their due dates
        for card in cards {
            let task = PeezyTimelineTask(
                id: card.id,
                title: card.title,
                subtitle: card.subtitle,
                time: formatTaskTime(card),
                type: mapTaskType(card, today: today),
                dueDate: card.dueDate,
                priority: card.priority.rawValue
            )

            // Determine which day this task belongs to
            let taskDate: Date
            if let dueDate = card.dueDate {
                taskDate = calendar.startOfDay(for: dueDate)
            } else {
                // No due date - put on today
                taskDate = today
            }

            let key = dateFormatter.string(from: taskDate)

            // Only add if within our timeline range
            if dayMap[key] != nil {
                dayMap[key]?.append(task)
                print("📅 Task '\(card.title)' added to \(key)")
            } else {
                // Task is outside timeline range - check if it's before today
                if taskDate < today {
                    // Overdue task - put on today
                    let todayKey = dateFormatter.string(from: today)
                    dayMap[todayKey]?.append(task)
                    print("📅 Overdue task '\(card.title)' added to today")
                } else {
                    // Future task beyond range - put at end
                    if let lastDate = calendar.date(byAdding: .day, value: timelineRange - 1, to: today) {
                        let lastKey = dateFormatter.string(from: lastDate)
                        dayMap[lastKey]?.append(task)
                        print("📅 Future task '\(card.title)' added to end of timeline")
                    }
                }
            }
        }

        // Convert to array, sorted by date
        var result: [PeezyDay] = []
        for i in 0..<timelineRange {
            if let date = calendar.date(byAdding: .day, value: i, to: today) {
                let key = dateFormatter.string(from: date)
                var tasks = dayMap[key] ?? []
                // Sort tasks by priority (highest first)
                tasks.sort { $0.priority > $1.priority }
                result.append(PeezyDay(date: date, tasks: tasks))
            }
        }

        return result
    }

    private func mapTaskType(_ card: PeezyCard, today: Date) -> PeezyTimelineTask.TaskType {
        let calendar = Calendar.current

        // Check priority
        if card.priority == .urgent {
            return .urgent
        }

        // Check if due today or overdue
        if let dueDate = card.dueDate {
            let dueDateStart = calendar.startOfDay(for: dueDate)
            if calendar.isDate(dueDateStart, inSameDayAs: today) {
                return .active
            } else if dueDateStart < today {
                return .urgent // Overdue
            }
        }

        return .future
    }

    private func formatTaskTime(_ card: PeezyCard) -> String {
        if let dueDate = card.dueDate {
            let components = Calendar.current.dateComponents([.hour, .minute], from: dueDate)
            // If time component is midnight (0:00), show "All Day"
            if components.hour == 0 && components.minute == 0 {
                return "All Day"
            }
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return formatter.string(from: dueDate)
        }
        return "Flexible"
    }

    // MARK: - Header View

    @ViewBuilder
    func HeaderView() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Mission Schedule")
                    .font(.title2.bold())
                    .foregroundColor(.white)
                Spacer()

                // Days until move indicator
                if let daysLeft = userState?.daysUntilMove, daysLeft > 0 {
                    Text("\(daysLeft) days to move")
                        .font(.caption)
                        .foregroundColor(.cyan)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(.white.opacity(0.1)))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 50)

            // Scrollable date strip
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(days) { day in
                            let isSameDate = Calendar.current.isDate(day.date, inSameDayAs: selectedDate)
                            let hasTask = !day.tasks.isEmpty
                            let isToday = Calendar.current.isDateInToday(day.date)

                            VStack(spacing: 6) {
                                Text(formatDate(day.date, "EEE").prefix(1))
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(isSameDate ? .black : .white.opacity(0.5))

                                Text(formatDate(day.date, "dd"))
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(isSameDate ? .black : .white)

                                // Task indicator dot
                                Circle()
                                    .fill(hasTask ? .cyan : .clear)
                                    .frame(width: 6, height: 6)
                            }
                            .frame(width: 45, height: 70)
                            .background {
                                if isSameDate {
                                    Capsule()
                                        .fill(.white)
                                        .matchedGeometryEffect(id: "ACTIVEDATE", in: namespace)
                                        .shadow(color: .white.opacity(0.5), radius: 10)
                                } else if isToday {
                                    Capsule()
                                        .fill(Color.cyan.opacity(0.2))
                                } else {
                                    Capsule()
                                        .fill(Color.white.opacity(0.05))
                                }
                            }
                            .id(day.id)
                            .onTapGesture {
                                withAnimation(.spring(response: 0.3)) {
                                    selectedDate = day.date
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 15)
                }
                .onAppear {
                    // Scroll to today on appear
                    if let todayDay = days.first(where: { Calendar.current.isDateInToday($0.date) }) {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation {
                                proxy.scrollTo(todayDay.id, anchor: .leading)
                            }
                        }
                    }
                }
            }
        }
    }

    func formatDate(_ date: Date, _ format: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}

// MARK: - Timeline Task Row
struct TimelineTaskRow: View {
    let task: PeezyTimelineTask
    private let charcoalColor = Color(red: 0.15, green: 0.15, blue: 0.17)

    var body: some View {
        HStack(spacing: 15) {
            // Status dot
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .shadow(color: statusColor.opacity(0.5), radius: 5)

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.headline)
                    .foregroundColor(.white)
                    .strikethrough(task.type == .completed)

                if !task.subtitle.isEmpty {
                    Text(task.subtitle)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }
            }

            Spacer()

            Text(task.time)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white.opacity(0.3))
        }
        .padding(16)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)

                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(charcoalColor.opacity(task.type == .active || task.type == .urgent ? 0.7 : 0.4))
            }
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(borderColor, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
        )
        .padding(.trailing, 20)
        .opacity(task.type == .completed ? 0.5 : 1.0)
    }

    private var statusColor: Color {
        switch task.type {
        case .active: return .cyan
        case .urgent: return .orange
        case .future: return .white.opacity(0.2)
        case .completed: return .green
        }
    }

    private var borderColor: Color {
        switch task.type {
        case .active: return .white.opacity(0.2)
        case .urgent: return .orange.opacity(0.3)
        case .future: return .white.opacity(0.05)
        case .completed: return .white.opacity(0.05)
        }
    }
}

// MARK: - Day Header
struct DayHeader: View {
    let date: Date
    var moveDate: Date?

    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }

    private var isMoveDay: Bool {
        guard let moveDate = moveDate else { return false }
        return Calendar.current.isDate(date, inSameDayAs: moveDate)
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(formatDate("EEE").uppercased())
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(isMoveDay ? .orange : (isToday ? .cyan : .cyan.opacity(0.7)))

            Text(formatDate("dd"))
                .font(.system(size: 34, weight: .bold))
                .foregroundColor(isMoveDay ? .orange : .white)

            if isToday {
                Text("TODAY")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.cyan)
            } else if isMoveDay {
                Text("MOVE DAY")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.orange)
            }
        }
        .frame(width: 60, height: 80)
        .frame(maxWidth: .infinity, alignment: .leading)
        .offset(x: 10)
    }

    private func formatDate(_ format: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}

// MARK: - Empty Day Row
struct EmptyDayRow: View {
    var body: some View {
        HStack {
            Spacer()
            Text("No tasks scheduled")
                .font(.caption)
                .italic()
                .foregroundColor(.white.opacity(0.3))
            Spacer()
        }
        .padding(.vertical, 20)
        .padding(.trailing, 20)
    }
}

// MARK: - Preview
#Preview {
    PeezyTaskStream()
}
