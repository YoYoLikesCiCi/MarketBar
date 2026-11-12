import Charts
import SwiftUI

struct QuoteTrendView: View {
    private struct LoadRequest: Equatable {
        let period: QuoteTrendPeriod
        let quoteUpdatedAt: Date?
        let retry: Int
    }

    private struct History {
        let period: QuoteTrendPeriod
        let points: [QuoteTrendPoint]
    }

    let id: String
    let store: MarketStore
    let tint: Color

    @State private var period = QuoteTrendPeriod.today
    @State private var history: History?
    @State private var failedPeriod: QuoteTrendPeriod?
    @State private var retry = 0
    @State private var hoverDate: Date?

    var body: some View {
        let quote = store.quotes[id]
        let request = LoadRequest(period: period, quoteUpdatedAt: quote?.fetchedAt, retry: retry)
        let calendar = QuoteTrendPoint.calendar(for: id)
        let points = period.plotPoints(history?.period == period ? history?.points ?? [] : [],
                                      latest: store.errors[id] == nil ? quote : nil, calendar: calendar)
        let hovered = hoverDate.flatMap { date in
            points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
        }

        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Text("价格走势").font(.subheadline.weight(.semibold))
                if let hovered {
                    let price = hovered.price.formatted(.number.precision(.fractionLength(2...4)))
                    Text("\(dateText(hovered.date, calendar: calendar)) · \(price)")
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
                } else if failedPeriod == period && !points.isEmpty {
                    Text("缓存").font(.caption).foregroundStyle(.secondary)
                } else if period == .today, let date = points.last?.date, !calendar.isDateInToday(date) {
                    Text("最近交易日 \(dayText(date, calendar: calendar))")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                SettingsSegments(title: "走势时间范围", values: QuoteTrendPeriod.allCases,
                                 selection: $period, label: \.rawValue)
            }

            Group {
                if !points.isEmpty {
                    chart(points, hovered: hovered, calendar: calendar)
                } else if failedPeriod == period {
                    HStack(spacing: 8) {
                        Text("走势暂不可用").foregroundStyle(.secondary)
                        Button("重试") { retry += 1 }.buttonStyle(.link)
                    }
                    .font(.caption)
                } else if history?.period == period {
                    Text(period == .today ? "暂无分时报价" : "本月暂无日线报价")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ProgressView().controlSize(.small).accessibilityLabel("正在载入走势")
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 108)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
        }
        .onChange(of: period) { hoverDate = nil }
        .task(id: request) {
            failedPeriod = nil
            do {
                let data = try await store.trend(for: id, period: request.period)
                try Task.checkCancellation()
                history = History(period: request.period, points: data)
            } catch {
                if !Task.isCancelled { failedPeriod = request.period }
            }
        }
    }

    private func chart(_ points: [QuoteTrendPoint], hovered: QuoteTrendPoint?, calendar: Calendar) -> some View {
        let low = points.map(\.price).min()!
        let high = points.map(\.price).max()!
        let padding = max(high - low, high * 0.001) * 0.15
        let first = points.first!.date
        let last = points.last!.date
        let duration = last.timeIntervalSince(first)
        let timePadding = max(60, duration * 0.025)
        let ticks = duration == 0 ? [first] : [first, first.addingTimeInterval(duration / 2), last]

        return Chart {
            ForEach(points) { point in
                LineMark(x: .value("时间", point.date), y: .value("价格", point.price))
                    .lineStyle(StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(tint)
            }
            if let hovered {
                RuleMark(x: .value("时间", hovered.date))
                    .foregroundStyle(.secondary.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            if let point = hovered ?? points.last {
                PointMark(x: .value("时间", point.date), y: .value("价格", point.price))
                    .symbolSize(26)
                    .foregroundStyle(tint)
            }
        }
        .chartXScale(domain: first.addingTimeInterval(-timePadding)...last.addingTimeInterval(timePadding))
        .chartYScale(domain: max(0, low - padding)...(high + padding))
        .chartXAxis {
            AxisMarks(values: ticks) { value in
                if let date = value.as(Date.self) {
                    let anchor: UnitPoint = date == last ? .trailing : date == first ? .leading : .center
                    AxisValueLabel(anchor: anchor) {
                        Text(dateText(date, calendar: calendar)).font(.caption2).monospacedDigit()
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.18))
                if let price = value.as(Double.self) {
                    AxisValueLabel {
                        Text(price, format: .number.precision(.fractionLength(0...4)))
                            .font(.caption2).monospacedDigit()
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Color.clear.contentShape(Rectangle()).onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        guard let anchor = proxy.plotFrame else { return }
                        let frame = geometry[anchor]
                        hoverDate = frame.contains(location) ? proxy.value(atX: location.x - frame.minX) : nil
                    case .ended:
                        hoverDate = nil
                    }
                }
            }
        }
        .accessibilityLabel(period == .today ? "分时价格走势" : "本月每日价格走势")
    }

    private func dateText(_ date: Date, calendar: Calendar) -> String {
        if period == .month { return dayText(date, calendar: calendar) }
        return date.formatted(dateStyle(calendar).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    private func dayText(_ date: Date, calendar: Calendar) -> String {
        date.formatted(dateStyle(calendar).month(.defaultDigits).day(.defaultDigits))
    }

    private func dateStyle(_ calendar: Calendar) -> Date.FormatStyle {
        Date.FormatStyle(locale: Locale(identifier: "zh_CN"), calendar: calendar, timeZone: calendar.timeZone)
    }
}
