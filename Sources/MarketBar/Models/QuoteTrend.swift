import Foundation

enum QuoteTrendPeriod: String, CaseIterable, Sendable {
    case today = "今日"
    case month = "本月"

    var calendarComponent: Calendar.Component { self == .today ? .day : .month }

    func plotPoints(_ history: [QuoteTrendPoint], latest: Quote?,
                    calendar: Calendar, now: Date = .now) -> [QuoteTrendPoint] {
        var points = history
        if let latest, let date = latest.quotedAt, latest.price.isFinite, latest.price > 0,
           history.last.map({ date >= $0.date }) ?? false {
            points.append(.init(date: date, price: latest.price))
        }

        switch self {
        case .today:
            guard let last = points.last else { return [] }
            return QuoteTrendPoint.ordered(points.filter { calendar.isDate($0.date, inSameDayAs: last.date) })
        case .month:
            guard let month = calendar.dateInterval(of: .month, for: now) else { return [] }
            return QuoteTrendPoint.ordered(points.compactMap { point in
                guard month.contains(point.date), point.date < month.end else { return nil }
                return QuoteTrendPoint(date: calendar.startOfDay(for: point.date), price: point.price)
            })
        }
    }
}

struct QuoteTrendPoint: Identifiable, Sendable {
    let date: Date
    let price: Double

    var id: Date { date }

    static func ordered(_ points: [Self]) -> [Self] {
        Dictionary(points.map { ($0.date, $0) }, uniquingKeysWith: { _, latest in latest })
            .values.sorted { $0.date < $1.date }
    }

    static func calendar(for id: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Instrument(id)?.timeZone ?? TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }
}
