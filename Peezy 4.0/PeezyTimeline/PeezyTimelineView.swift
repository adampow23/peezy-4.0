import SwiftUI

// MARK: - 1. DATA MODELS
struct PeezyDay: Identifiable {
    var id: String = UUID().uuidString
    var date: Date
    var tasks: [PeezyTask]
}

struct PeezyTask: Identifiable {
    var id: String = UUID().uuidString
    var title: String
    var subtitle: String
    var time: String
    var type: TaskType
    
    enum TaskType {
        case active
        case future
        case completed
    }
}

// MARK: - 2. MAIN VIEW
struct PeezyTaskStream: View {
    // View Properties
    @State private var days: [PeezyDay] = generateMockDays()
    @State private var selectedDate: Date = Date()
    @Namespace private var namespace
    
    var body: some View {
        ZStack {
            // A. The Midnight Background
            InteractiveBackground()
            
            VStack(spacing: 0) {
                // B. The Top Strip (Week Selector)
                HeaderView()
                    .padding(.bottom, 10)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                    .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
                
                GeometryReader { geometry in
                    let size = geometry.size
                    
                    ScrollView(.vertical, showsIndicators: false) {
                        // THE MAGIC: Pinned Section Headers
                        LazyVStack(spacing: 15, pinnedViews: [.sectionHeaders]) {
                            ForEach(days) { day in
                                let date = day.date
                                let isLast = days.last?.id == day.id
                                
                                Section {
                                    // THE TASKS (Right Side)
                                    VStack(alignment: .leading, spacing: 15) {
                                        if day.tasks.isEmpty {
                                            EmptyRow()
                                        } else {
                                            ForEach(day.tasks) { task in
                                                CharcoalTaskRow(task: task)
                                            }
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.leading, 80) // Push content Right
                                    .padding(.top, -70)    // Pull content Up to align with Header
                                    .padding(.bottom, 10)
                                    // Ensure last section fills screen for scroll feeling
                                    .frame(minHeight: isLast ? size.height - 110 : nil, alignment: .top)
                                    
                                } header: {
                                    // THE DATE (Left Side - Sticky)
                                    VStack(spacing: 4) {
                                        Text(formatDate(date, "EEE").uppercased())
                                            .font(.caption)
                                            .fontWeight(.bold)
                                            .foregroundColor(.cyan)
                                        
                                        Text(formatDate(date, "dd"))
                                            .font(.system(size: 34, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                                    .frame(width: 60, height: 70)
                                    .background(
                                        // Glass blur behind the sticky header so text doesn't clash
                                        Rectangle()
                                            .fill(.ultraThinMaterial)
                                            .opacity(0.01) // Almost invisible, just for hit testing if needed
                                            .blur(radius: 5)
                                    )
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .offset(x: 10) // Padding from left edge
                                }
                            }
                        }
                        .padding(.top, 20)
                    }
                }
            }
        }
        .edgesIgnoringSafeArea(.bottom)
    }
    
    // MARK: - TOP HEADER VIEW
    @ViewBuilder
    func HeaderView() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Mission Schedule")
                    .font(.title2.bold())
                    .foregroundColor(.white)
                Spacer()
                Image(systemName: "line.3.horizontal.decrease.circle.fill")
                    .font(.title2)
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.horizontal, 20)
            .padding(.top, 50) // Safe Area
            
            // Week Strip
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(days) { day in
                        let date = day.date
                        let isSameDate = Calendar.current.isDate(date, inSameDayAs: selectedDate)
                        
                        VStack(spacing: 6) {
                            Text(formatDate(date, "EEE").prefix(1))
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(isSameDate ? .black : .white.opacity(0.5))
                            
                            Text(formatDate(date, "dd"))
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundColor(isSameDate ? .black : .white)
                        }
                        .frame(width: 45, height: 60)
                        .background {
                            if isSameDate {
                                Capsule()
                                    .fill(.white)
                                    .matchedGeometryEffect(id: "ACTIVEDATE", in: namespace)
                                    .shadow(color: .white.opacity(0.5), radius: 10)
                            } else {
                                Capsule()
                                    .fill(Color.white.opacity(0.05))
                            }
                        }
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3)) {
                                selectedDate = date
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 15)
            }
        }
    }
    
    // Helper
    func formatDate(_ date: Date, _ format: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}

// MARK: - 3. CHARCOAL TASK ROW (The Card)
struct CharcoalTaskRow: View {
    let task: PeezyTask
    private let charcoalColor = Color(red: 0.15, green: 0.15, blue: 0.17)
    
    var body: some View {
        HStack(spacing: 15) {
            // Dot Indicator
            Circle()
                .fill(statusColor(task.type))
                .frame(width: 8, height: 8)
                .shadow(color: statusColor(task.type).opacity(0.5), radius: 5)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.headline)
                    .foregroundColor(.white)
                    .strikethrough(task.type == .completed)
                
                Text(task.subtitle)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
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
                // The Charcoal Glass
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
                
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(charcoalColor.opacity(task.type == .active ? 0.7 : 0.4))
            }
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        task.type == .active ? Color.white.opacity(0.2) : Color.white.opacity(0.05),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
        )
        .padding(.trailing, 20)
        .opacity(task.type == .completed ? 0.5 : 1.0)
    }
    
    func statusColor(_ type: PeezyTask.TaskType) -> Color {
        switch type {
        case .active: return .cyan
        case .future: return .white.opacity(0.2)
        case .completed: return .green
        }
    }
}

struct EmptyRow: View {
    var body: some View {
        HStack {
            Spacer()
            Text("No missions scheduled.")
                .font(.caption)
                .italic()
                .foregroundColor(.white.opacity(0.3))
            Spacer()
        }
        .padding(.vertical, 20)
        .padding(.trailing, 20)
    }
}

// MARK: - 4. MOCK DATA GENERATOR
func generateMockDays() -> [PeezyDay] {
    let calendar = Calendar.current
    let today = DateProvider.shared.now
    var days: [PeezyDay] = []
    
    for i in 0..<7 {
        if let date = calendar.date(byAdding: .day, value: i, to: today) {
            
            var tasks: [PeezyTask] = []
            
            // Add fake data based on index
            if i == 0 {
                tasks.append(PeezyTask(title: "Confirm Internet", subtitle: "Xfinity Quote Ready", time: "2:00 PM", type: .active))
                tasks.append(PeezyTask(title: "Sign Lease", subtitle: "Waiting on Landlord", time: "4:00 PM", type: .active))
            } else if i == 1 {
                tasks.append(PeezyTask(title: "Order Boxes", subtitle: "Amazon Basics", time: "9:00 AM", type: .future))
                tasks.append(PeezyTask(title: "Call Movers", subtitle: "Verify Insurance", time: "11:00 AM", type: .future))
            } else if i == 2 {
                 // Empty day
            } else {
                tasks.append(PeezyTask(title: "Change Address", subtitle: "USPS Online", time: "All Day", type: .future))
            }
            
            days.append(PeezyDay(date: date, tasks: tasks))
        }
    }
    return days
}

// Re-using background for standalone preview
struct InteractiveBackground2: View {
    @State private var animate = false
    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.1).ignoresSafeArea()
            GeometryReader { geo in
                ZStack {
                    Circle().fill(Color.blue.opacity(0.2)).frame(width: 300).blur(radius: 60)
                        .offset(x: animate ? -50 : 50, y: animate ? -100 : 50)
                    Circle().fill(Color.purple.opacity(0.2)).frame(width: 300).blur(radius: 60)
                        .offset(x: animate ? 100 : -100, y: animate ? 200 : -50)
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 10).repeatForever(autoreverses: true)) { animate.toggle() }
        }
    }
}

#Preview {
    PeezyTaskStream()
}
