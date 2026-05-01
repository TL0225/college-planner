import re

with open("/Users/timothy/Desktop/College/College/Calendar/CalendarView.swift", "r") as f:
    code = f.read()

# 1. Update the Picker
code = code.replace(
    'Picker("View Mode", selection: $activeViewMode)',
    'Picker("", selection: $activeViewMode)'
)
code = code.replace(
    '.pickerStyle(.segmented)',
    '.pickerStyle(.segmented)\n                .labelsHidden()'
)


# 2. Add Time Indicator
time_indicator = """
                    // Events
                    HStack(spacing: 0) {
                        Spacer().frame(width: 50)
                        ForEach(days, id: \\.self) { date in
                            let timedEvents = getEvents(for: date).filter { !$0.isAllDay }
                            let layouts = calculateLayout(for: timedEvents)
                            GeometryReader { geo in
                                ForEach(0..<layouts.count, id: \\.self) { i in
                                    let layout = layouts[i]
                                    let event = layout.0
                                    let eventWidth = (geo.size.width - 8) / CGFloat(layout.2)
                                    let eventX = CGFloat(layout.1) * eventWidth
                                    TimeEventBlock(event: event)
                                        .frame(width: eventWidth, height: height(for: event))
                                        .offset(x: eventX, y: offset(for: event))
                                        .padding(.trailing, layout.2 > 1 ? 2 : 0)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    
                    // Current Time Indicator
                    if calendar.isDateInToday(currentDate) || activeViewMode == .week {
                        let now = Date()
                        let c = calendar.dateComponents([.hour, .minute], from: now)
                        let currentOffset = CGFloat(c.hour ?? 0) * 60.0 + CGFloat(c.minute ?? 0)
                        
                        if currentOffset > 0 {
                            HStack(spacing: 0) {
                                Spacer().frame(width: 47)
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 6, height: 6)
                                Rectangle()
                                    .fill(Color.red)
                                    .frame(height: 1)
                            }
                            .offset(y: currentOffset - 3)
                            .allowsHitTesting(false)
                        }
                    }
"""

replacement_target = """                    // Events
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
                    }"""

if replacement_target in code:
    code = code.replace(replacement_target, time_indicator)
else:
    print("WARNING: Events block not found!")


# 3. Add calculateLayout method
layout_method = """
    private func calculateLayout(for events: [CalEvent]) -> [(CalEvent, Int, Int)] {
        var result: [(CalEvent, Int, Int)] = []
        var clusters: [[CalEvent]] = []
        var currentCluster: [CalEvent] = []
        var clusterEnd: Date = .distantPast
        
        let sortedEvents = events.sorted { ($0.startDate ?? Date()) < ($1.startDate ?? Date()) }
        
        for event in sortedEvents {
            let start = event.startDate ?? Date()
            if start >= clusterEnd {
                if !currentCluster.isEmpty {
                    clusters.append(currentCluster)
                }
                currentCluster = [event]
                clusterEnd = event.endDate ?? Date()
            } else {
                currentCluster.append(event)
                if (event.endDate ?? Date()) > clusterEnd {
                    clusterEnd = event.endDate ?? Date()
                }
            }
        }
        if !currentCluster.isEmpty {
            clusters.append(currentCluster)
        }
        
        for cluster in clusters {
            var columns: [Date] = []
            var clusterResult: [(CalEvent, Int)] = []
            for event in cluster {
                let start = event.startDate ?? Date()
                var placed = false
                for i in 0..<columns.count {
                    if columns[i] <= start {
                        columns[i] = event.endDate ?? Date()
                        clusterResult.append((event, i))
                        placed = true
                        break
                    }
                }
                if !placed {
                    columns.append(event.endDate ?? Date())
                    clusterResult.append((event, columns.count - 1))
                }
            }
            let maxCols = columns.count
            for cr in clusterResult {
                result.append((cr.0, cr.1, maxCols))
            }
        }
        
        return result
    }
"""
if "calculateLayout" not in code:
    code = code.replace("private func dayHeader", layout_method + "\n    private func dayHeader")

# 4. Modify colors
if "case management" not in code:
    code = code.replace("case club", "case club\n    case management\n    case computerScience")
    code = code.replace("""case .extracurricular: return Color(hex: "10B981")""", """case .extracurricular: return Color(hex: "10B981")
        case .management: return Color.orange
        case .computerScience: return Color.blue""")

# Modify parsing logic
parsing_logic = """
            let title = ev.title ?? "Event"
            var type: EventType = .classEvent
            let lowerTitle = title.lowercased()
            if lowerTitle.contains("mgs") {
                type = .management
            } else if lowerTitle.contains("cse") || lowerTitle.contains("csc") {
                type = .computerScience
            } else if lowerTitle.contains("lec") || lowerTitle.contains("lecture") {
                type = .lecture
            } else if lowerTitle.contains("lab") || lowerTitle.contains("lr") || lowerTitle.contains("recitation") {
                type = .lab
            } else if lowerTitle.contains("meeting") || lowerTitle.contains("club") || lowerTitle.contains("eboard") || lowerTitle.contains("bowling") {
                type = .extracurricular
            } else if lowerTitle.contains("exam") || lowerTitle.contains("midterm") {
                type = .deadline
            }
            
            let start = ev.startDate ?? date
            let end = (ev.value(forKey: "endDate") as? Date) ?? start.addingTimeInterval(3600)
            
            let duration = end.timeIntervalSince(start)
            let isAllDayEvent = duration >= 86000 || (calendar.component(.hour, from: start) == 0 && calendar.component(.minute, from: start) == 0 && calendar.component(.hour, from: end) == 0 && calendar.component(.minute, from: end) == 0 && duration >= 3600) || lowerTitle.contains("first day") || lowerTitle.contains("break") || lowerTitle.contains("all day")
            
            dayEvents.append(CalEvent(title: title, type: type, isImportant: type == .deadline, startDate: start, endDate: end, isAllDay: isAllDayEvent))"""

old_parsing = """            let title = ev.title ?? "Event"
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
            
            dayEvents.append(CalEvent(title: title, type: type, isImportant: type == .deadline, startDate: start, endDate: end, isAllDay: false))"""

if old_parsing in code:
    code = code.replace(old_parsing, parsing_logic)

# Make lines transparent
code = code.replace("""Divider()
                                    .background(Color(hex: "F3F4F6"))""", """Divider()
                                    .overlay(Color(hex: "F3F4F6").opacity(0.1))""")


with open("/Users/timothy/Desktop/College/College/Calendar/CalendarView.swift", "w") as f:
    f.write(code)
print("done")
