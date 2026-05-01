import sys

file_path = "/Users/timothy/Desktop/College/College/Calendar/CalendarView.swift"

code = """import SwiftUI
import CoreData

struct CalendarView: View {
    @Binding var activePage: AppPage
    
    @Environment(\\.managedObjectContext) private var viewContext
    
    @FetchRequest(
        entity: CalendarEventEntity.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \\CalendarEventEntity.startDate, ascending: true)],
        animation: .default)
    private var events: FetchedResults<CalendarEventEntity>
    
    @FetchRequest(
        entity: TaskEntity.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \\TaskEntity.dueDate, ascending: true)],
        animation: .default)
    private var tasks: FetchedResults<TaskEntity>
    
    @State private var currentDate: Date = Date()
    @State private var activeViewMode: ViewMode = .month
    
    enum ViewMode: String, CaseIterable {
        case month = "Month"
        case week = "Week"
        case day = "Day"
    }
    
    private var calendar: Calendar {
        var cal = Calendar.current
        cal.firstWeekday = 1 // Sunday
        return cal
    }
    
    private var headerDateString: String {
        let formatter = DateFormatter()
        switch activeViewMode {
        case .month:
            formatter.dateFormat = "MMMM yyyy"
        case .week:
            formatter.dateFormat = "MMM d, yyyy"
        case .day:
            formatter.dateFormat = "MMMM d, yyyy"
        }
        return formatter.string(from: currentDate).uppercased()
    }
    
    private func shiftDate(by value: Int) {
        switch activeViewMode {
        case .month:
            currentDate = calendar.date(byAdding: .month, value: value, to: currentDate) ?? currentDate
        case .week:
            currentDate = calendar.date(byAdding: .weekOfYear, value: value, to: currentDate) ?? currentDate
        case .day:
            currentDate = calendar.date(byAdding: .day, value: value, to: currentDate) ?? currentDate
        }
    }
    
    private var todayString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "TODAY • " + formatter.string(from: Date()).uppercased()
    }
    
    private func getDaysForCurrentView() -> [Date] {
        switch activeViewMode {
        case .month:
            guard let monthInterval = calendar.dateInterval(of: .month, for: currentDate) else { return [] }
            guard let monthFirstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start) else { return [] }
            guard let monthLastWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.end - 1) else { return [] }
            
            let start = monthFirstWeek.start
            let end = monthLastWeek.end
            
            var dates: [Date] = []
            var d = start
            while d < end {
                dates.append(d)
                if let next = calendar.date(byAdding: .day, value: 1, to: d) {
                    d = next
                } else {
                    break
                }
            }
            return dates
            
        case .week:
            guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: currentDate) else { return [] }
            var dates: [Date] = []
            var d = weekInterval.start
            while d < weekInterval.end {
                dates.append(d)
                if let next = calendar.date(byAdding: .day, value: 1, to: d) {
                    d = next
                } else {
                    break
                }
            }
            return dates
            
        case .day:
            return [calendar.startOfDay(for: currentDate)]
        }
    }
    
    private func getEvents(for date: Date) -> [CalEvent] {
        var dayEvents: [CalEvent] = []
        
        let dayCalendarEvents = events.filter { event in
            guard let start = event.startDate else { return false }
            return calendar.isDate(start, inSameDayAs: date)
        }
        
        for ev in dayCalendarEvents {
            let title = ev.title ?? "Event"
            var type: EventType = .classEvent
            let lowerTitle = title.lowercased()
            if lowerTitle.contains("lec") || lowerTitle.contains("lecture") {
                type = .lecture
            } else if lowerTitle.contains("lab") || lowerTitle.contains("lr") || lowerTitle.contains("recitation") {
                type = .lab
            } else if lowerTitle.contains("meeting") || lowerTitle.contains("club") || lowerTitle.contains("eboard") {
                type = .extracurricular
            } else if lowerTitle.contains("exam") || lowerTitle.contains("midterm") {
                type = .deadline
            }
            
            let start = ev.startDate ?? date
            let end = (ev.value(forKey: "endDate") as? Date) ?? start.addingTimeInterval(3600)
            
            dayEvents.append(CalEvent(title: title, type: type, isImportant: type == .deadline, startDate: start, endDate: end, isAllDay: false))
        }
        
        let dayTasks = tasks.filter { task in
            guard let due = task.dueDate else { return false }
            return calendar.isDate(due, inSameDayAs: date)
        }
        
        for task in dayTasks {
            dayEvents.append(CalEvent(title: task.title ?? "Task", type: .deadline, isImportant: true, startDate: task.dueDate ?? date, endDate: task.dueDate ?? date, isAllDay: true))
        }
        
        dayEvents.sort {
            if $0.isImportant && !$1.isImportant { return true }
            if !$0.isImportant && $1.isImportant { return false }
            if let s1 = $0.startDate, let s2 = $1.startDate { return s1 < s2 }
            return $0.title < $1.title
        }
        
        return dayEvents
    }
    
    private var todayEvents: [CalendarEventEntity] {
        events.filter { event in
            guard let start = event.startDate else { return false }
            return calendar.isDate(start, inSameDayAs: Date())
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            mainCalendarContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            sidePanel
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: "F4F5F7"))
    }
    
    @ViewBuilder
    private var mainCalendarContent: some View {
        VStack(spacing: 0) {
            // Header Row (Month & Year) and View Switcher
            HStack {
                Picker("View Mode", selection: $activeViewMode) {
                    ForEach(ViewMode.allCases, id: \\.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                
                Spacer()
                
                HStack(spacing: 16) {
                    Button(action: { shiftDate(by: -1) }) {
                        Image(systemName: "chevron.left")
                    }
                    Text(headerDateString)
                        .font(.system(size: 16, weight: .bold))
                        .frame(minWidth: 140)
                    Button(action: { shiftDate(by: 1) }) {
                        Image(systemName: "chevron.right")
                    }
                }
                .foregroundColor(Color(hex: "111827"))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            
            if activeViewMode == .month {
                monthGridView
            } else {
                timeGridView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.03), radius: 10, y: 4)
        .padding(.vertical, 24)
        .padding(.leading, 24)
        .padding(.trailing, 24)
    }

    private var monthGridView: some View {
        VStack(spacing: 0) {
            // Header Row (Days)
            HStack(spacing: 0) {
                let headers = getDaysForCurrentView().prefix(7).map { $0 }
                ForEach(headers, id: \\.timeIntervalSince1970) { date in
                    let dayString = {
                        let f = DateFormatter()
                        f.dateFormat = "EEE"
                        return f.string(from: date).uppercased()
                    }()
                    Text(dayString)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(hex: "9CA3AF"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
            }
            
            Divider().background(Color(hex: "E5E7EB"))
            
            let days = getDaysForCurrentView()
            let rows = max(1, days.count / 7)
            
            if !days.isEmpty {
                ForEach(0..<rows, id: \\.self) { rowIndex in
                    let startIdx = rowIndex * 7
                    let endIdx = min(startIdx + 7, days.count)
                    let rowDays = (startIdx..<endIdx).map { colIndex -> (Int, [CalEvent]?, Bool) in
                        let date = days[colIndex]
                        let dayNum = calendar.component(.day, from: date)
                        let evs = getEvents(for: date)
                        let isCurrent = calendar.isDateInToday(date)
                        return (dayNum, evs.isEmpty ? nil : evs, isCurrent)
                    }
                    
                    MonthCalendarRow(days: rowDays, isLast: rowIndex == rows - 1)
                }
            }
        }
    }
    
    // Y-Axis Time Grid
    private var timeGridView: some View {
        VStack(spacing: 0) {
            // All-Day Shelf + Headers
            let days = getDaysForCurrentView()
            HStack(spacing: 0) {
                // Time column header spacer
                Spacer().frame(width: 50)
                ForEach(days, id: \\.self) { date in
                    VStack(spacing: 4) {
                        let isToday = calendar.isDateInToday(date)
                        Text(dayHeader(for: date))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(isToday ? Color.blue : Color(hex: "9CA3AF"))
                        
                        Text("\\(calendar.component(.day, from: date))")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(isToday ? .white : Color(hex: "111827"))
                            .frame(width: 32, height: 32)
                            .background(isToday ? Color.blue : Color.clear)
                            .clipShape(Circle())
                        
                        // All-Day Events
                        let allDay = getEvents(for: date).filter { $0.isAllDay }
                        VStack(spacing: 4) {
                            ForEach(allDay) { event in
                                Text(event.title)
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .frame(maxWidth: .infinity)
                                    .background(Color.red.opacity(0.8))
                                    .cornerRadius(4)
                            }
                        }
                        .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
            }
            .border(Color(hex: "E5E7EB"), width: 1, edges: [.bottom])
            
            // Time Grid Scroll
            ScrollView {
                ZStack(alignment: .topLeading) {
                    // Hour markers and grid lines
                    VStack(spacing: 0) {
                        ForEach(0..<24, id: \\.self) { hour in
                            HStack(alignment: .top, spacing: 0) {
                                Text("\\(hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)) \\(hour >= 12 ? "PM" : "AM")")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(Color(hex: "9CA3AF"))
                                    .frame(width: 50, alignment: .trailing)
                                    .padding(.trailing, 8)
                                    .offset(y: -6)
                                
                                Divider()
                                    .background(Color(hex: "F3F4F6"))
                            }
                            .frame(height: 60)
                        }
                    }
                    
                    // Events
                    HStack(spacing: 0) {
                        Spacer().frame(width: 50)
                        ForEach(days, id: \\.self) { date in
                            let timedEvents = getEvents(for: date).filter { !$0.isAllDay }
                            GeometryReader { geo in
                                ForEach(timedEvents) { event in
                                    TimeEventBlock(event: event)
                                        .frame(width: geo.size.width - 8, height: height(for: event))
                                        .offset(y: offset(for: event))
                                        .padding(.horizontal, 4)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                .frame(height: 24 * 60) // 24 hours * 60pt
            }
        }
    }
    
    private func dayHeader(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f.string(from: date).uppercased()
    }
    
    private func offset(for event: CalEvent) -> CGFloat {
        guard let start = event.startDate else { return 0 }
        let c = calendar.dateComponents([.hour, .minute], from: start)
        return CGFloat(c.hour ?? 0) * 60.0 + CGFloat(c.minute ?? 0)
    }
    
    private func height(for event: CalEvent) -> CGFloat {
        guard let start = event.startDate, let end = event.endDate else { return 60 }
        let duration = end.timeIntervalSince(start) / 60.0
        return max(30, CGFloat(duration))
    }

    private var sidePanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Academic Events")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Color(hex: "111827"))
                    Text(todayString)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(hex: "9CA3AF"))
                }
                Spacer()
                Image(systemName: "ellipsis")
                    .foregroundColor(Color(hex: "9CA3AF"))
                    .font(.system(size: 18))
            }
            .padding(.top, 32)
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    let todaysContent = todayEvents
                    if todaysContent.isEmpty {
                        Text("No events today")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color(hex: "9CA3AF"))
                            .padding(.top, 24)
                    } else {
                        ForEach(todaysContent, id: \\.objectID) { event in
                            let timeString: String = {
                                guard let start = event.startDate else { return "" }
                                let formatter = DateFormatter()
                                formatter.timeStyle = .short
                                return formatter.string(from: start)
                            }()
                            
                            SideEventCard(
                                badge: "EVENT", badgeColor: .white, badgeBg: Color(hex: "3B82F6"),
                                time: timeString, title: event.title ?? "Event",
                                icon: "mappin.and.ellipse", iconText: "Scheduled", iconColor: Color(hex: "3B82F6")
                            )
                        }
                    }
                }
            }
            
            Spacer()
            
            Button(action: {}) {
                Text("View Full Timeline")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(hex: "111827"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(hex: "F3F4F6"))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 24)
        }
        .frame(width: 320)
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .background(.ultraThinMaterial) // Vibrancy
    }
}

// Data Models & Subcomponents

fileprivate enum EventType {
    case deadline
    case classEvent
    case lecture
    case lab
    case extracurricular
    case personal
    case club
}

fileprivate struct CalEvent: Identifiable {
    let id = UUID()
    let title: String
    let type: EventType
    let isImportant: Bool
    
    var startDate: Date?
    var endDate: Date?
    var isAllDay: Bool
}

// Block for Time Grid
fileprivate struct TimeEventBlock: View {
    let event: CalEvent
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 0) {
            // Leading Edge Bar
            Rectangle()
                .fill(baseColor)
                .frame(width: 4)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(textColor)
                
                // Truncation logic: only show extra info if it's tall enough
                GeometryReader { geo in
                    if geo.size.height > 25 {
                        Text(timeString)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(textColor.opacity(0.8))
                    }
                }
            }
            .padding(4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(baseColor.opacity(isHovering ? 0.25 : 0.15))
        }
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(baseColor.opacity(0.3), lineWidth: 0.5)
        )
        .onHover { hover in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovering = hover
            }
        }
    }
    
    private var baseColor: Color {
        switch event.type {
        case .lecture: return Color(hex: "3B82F6")
        case .lab: return Color(hex: "8B5CF6")
        case .deadline: return Color(hex: "EF4444")
        case .extracurricular: return Color(hex: "10B981")
        default: return Color(hex: "6366F1")
        }
    }
    
    private var textColor: Color {
        return Color(hex: "111827")
    }
    
    private var timeString: String {
        guard let s = event.startDate, let e = event.endDate else { return "" }
        let f = DateFormatter()
        f.timeStyle = .short
        return "\\(f.string(from: s)) - \\(f.string(from: e))"
    }
}

fileprivate struct MonthCalendarRow: View {
    let days: [(Int, [CalEvent]?, Bool)]
    let isLast: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(0..<days.count, id: \\.self) { index in
                    let day = days[index]
                    MonthCalendarCell(dayNumber: day.0, events: day.1 ?? [], isCurrentDay: day.2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    if index < days.count - 1 {
                        Divider().background(Color(hex: "E5E7EB"))
                    }
                }
            }
            .frame(maxHeight: .infinity)
            
            if !isLast {
                Divider().background(Color(hex: "E5E7EB"))
            }
        }
    }
}

fileprivate struct MonthCalendarCell: View {
    let dayNumber: Int
    let events: [CalEvent]
    let isCurrentDay: Bool
    let maxVisibleEvents = 4
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if isCurrentDay {
                    Text("\\(dayNumber)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 24, height: 24)
                        .background(Color(hex: "3B82F6"))
                        .clipShape(Circle())
                } else {
                    Text("\\(dayNumber)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(events.isEmpty ? Color(hex: "9CA3AF") : Color(hex: "374151"))
                        .padding(.leading, 4)
                        .padding(.top, 4)
                }
                Spacer()
            }
            .padding(.top, 6)
            .padding(.horizontal, 6)
            
            VStack(alignment: .leading, spacing: 3) {
                let displayedEvents = Array(events.prefix(maxVisibleEvents))
                ForEach(displayedEvents) { event in
                    EventPill(event: event)
                }
                
                if events.count > maxVisibleEvents {
                    Text("+ \\(events.count - maxVisibleEvents) more")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color(hex: "6B7280"))
                        .padding(.leading, 6)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 6)
            
            Spacer(minLength: 0)
        }
    }
}

fileprivate struct EventPill: View {
    let event: CalEvent
    
    var body: some View {
        HStack(spacing: 4) {
            if event.isImportant {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 8))
            } else if event.type == .lecture || event.type == .classEvent {
                Image(systemName: "book.fill")
                    .font(.system(size: 8))
            } else if event.type == .lab {
                Image(systemName: "flask.fill")
                    .font(.system(size: 8))
            }
            
            Text(event.title)
                .font(.system(size: 9, weight: event.isImportant ? .bold : .medium))
                .lineLimit(1)
        }
        .foregroundColor(textColor)
        .padding(.horizontal, 6)
        .frame(height: 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundColor)
        .cornerRadius(4)
    }
    
    private var textColor: Color {
        switch event.type {
        case .deadline: return .white
        case .lecture, .classEvent: return .white
        case .lab: return .white
        case .extracurricular, .club: return .white
        default: return Color(hex: "4B5563")
        }
    }
    
    private var backgroundColor: Color {
        switch event.type {
        case .deadline: return Color(hex: "EF4444")
        case .lecture, .classEvent: return Color(hex: "3B82F6")
        case .lab: return Color(hex: "8B5CF6")
        case .extracurricular, .club: return Color(hex: "10B981")
        default: return Color(hex: "F3F4F6")
        }
    }
}

fileprivate struct SideEventCard: View {
    let badge: String
    let badgeColor: Color
    let badgeBg: Color
    let time: String
    let title: String
    let icon: String
    let iconText: String
    let iconColor: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(badge)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(badgeColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(badgeBg)
                    .clipShape(Capsule())
                
                Spacer()
                
                Text(time)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(hex: "9CA3AF"))
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Color(hex: "111827"))
                
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.system(size: 11))
                        .foregroundColor(iconColor)
                    Text(iconText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(iconColor == Color(hex: "9CA3AF") ? Color(hex: "6B7280") : iconColor)
                }
            }
        }
        .padding(20)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.05), radius: 8, y: 2) // Subtle, lifting shadow
    }
}

fileprivate extension View {
    func border(_ color: Color, width: CGFloat, edges: [Edge]) -> some View {
        overlay(EdgeBorder(width: width, edges: edges).foregroundColor(color))
    }
}

fileprivate struct EdgeBorder: Shape {
    var width: CGFloat
    var edges: [Edge]
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for edge in edges {
            var x: CGFloat = 0, y: CGFloat = 0, w: CGFloat = rect.width, h: CGFloat = rect.height
            switch edge {
            case .top:    h = width
            case .bottom: y = rect.maxY - width; h = width
            case .leading:  w = width
            case .trailing: x = rect.maxX - width; w = width
            }
            path.addRect(CGRect(x: x, y: y, width: w, height: h))
        }
        return path
    }
}
"""

with open(file_path, "w") as f:
    f.write(code)

print("Updated CalendarView.swift successfully!")
