import Foundation

extension Date {
    /// Returns a relative time string (e.g., "2h ago", "Yesterday", "Mar 15")
    var timeAgo: String {
        let now = Date()
        let components = Calendar.current.dateComponents(
            [.year, .month, .weekOfYear, .day, .hour, .minute],
            from: self,
            to: now
        )

        // Less than a minute
        if let minutes = components.minute, minutes < 1 {
            return "Just now"
        }

        // Less than an hour
        if let minutes = components.minute, minutes < 60, let hours = components.hour, hours < 1 {
            return "\(minutes)m ago"
        }

        // Less than a day
        if let hours = components.hour, hours < 24, let days = components.day, days < 1 {
            return "\(hours)h ago"
        }

        // Yesterday
        if Calendar.current.isDateInYesterday(self) {
            return "Yesterday"
        }

        // This week
        if let days = components.day, days < 7 {
            return "\(days)d ago"
        }

        // This year
        if let years = components.year, years < 1 {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: self)
        }

        // Older
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: self)
    }

    /// Returns a formatted date string for display
    var displayDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: self)
    }

    /// Returns a formatted date and time string
    var displayDateTime: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }

    /// Returns start of day
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }

    /// Returns end of day
    var endOfDay: Date {
        var components = DateComponents()
        components.day = 1
        components.second = -1
        return Calendar.current.date(byAdding: components, to: startOfDay) ?? self
    }

    /// Check if date is today
    var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }

    /// Check if date is yesterday
    var isYesterday: Bool {
        Calendar.current.isDateInYesterday(self)
    }

    /// Check if date is this week
    var isThisWeek: Bool {
        Calendar.current.isDate(self, equalTo: Date(), toGranularity: .weekOfYear)
    }

    /// Check if date is this month
    var isThisMonth: Bool {
        Calendar.current.isDate(self, equalTo: Date(), toGranularity: .month)
    }
}

// MARK: - Date Grouping

extension Array where Element == Document {
    /// Group documents by date for timeline display
    func groupedByDate() -> [(date: Date, title: String, documents: [Document])] {
        let calendar = Calendar.current

        let grouped = Dictionary(grouping: self) { document in
            calendar.startOfDay(for: document.createdAt)
        }

        return grouped.map { date, docs in
            let title: String
            if calendar.isDateInToday(date) {
                title = "Today"
            } else if calendar.isDateInYesterday(date) {
                title = "Yesterday"
            } else if calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear) {
                title = "This Week"
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "MMMM d"
                title = formatter.string(from: date)
            }

            return (date: date, title: title, documents: docs.sorted { $0.createdAt > $1.createdAt })
        }
        .sorted { $0.date > $1.date }
    }
}
