import Foundation

struct PriceAlertRule: Codable, Identifiable {
    enum Metric: String, Codable, CaseIterable {
        case targetPrice, percent, amount
        var label: String {
            switch self {
            case .targetPrice: "目标价格"
            case .percent: "涨跌幅"
            case .amount: "价格变动"
            }
        }
    }

    enum Direction: String, Codable, CaseIterable {
        case either, up, down
        var label: String {
            switch self {
            case .either: "双向"
            case .up: "上涨"
            case .down: "下跌"
            }
        }
    }

    struct Criteria: Codable, Equatable {
        let instrumentID: String
        let metric: Metric
        let direction: Direction
        let threshold: Decimal
        let referencePrice: Decimal?

        var unit: String {
            if metric == .percent { return "%" }
            if instrumentID == Instrument.goldID { return "元/克" }
            return (Instrument(instrumentID)?.currency ?? "CNY") + "/单位"
        }

        var summary: String {
            if metric == .targetPrice {
                let comparison = direction == .up ? "≥" : "≤"
                return "价格 \(comparison) \(PriceAlertRule.numberText(threshold)) \(unit)"
            }
            let reference = referencePrice.map { "较 \(PriceAlertRule.numberText($0))" } ?? "较昨收"
            return "\(reference) · \(direction.label) · ≥ \(PriceAlertRule.numberText(threshold)) \(unit)"
        }
    }

    struct Reading: Equatable {
        let reference: Decimal
        let direction: Direction?
        let magnitude: Decimal
    }

    let id: UUID
    let criteria: Criteria
    var enabled = true
    var lastDirection: Direction?
    var lastReference: Decimal?
    var lastTriggeredAt: Date?

    func reading(for quote: Quote) -> Reading? {
        guard quote.price.isFinite, quote.price > 0,
              let price = Decimal(string: String(quote.price), locale: Locale(identifier: "en_US_POSIX")) else {
            return nil
        }
        if criteria.metric == .targetPrice {
            let target = criteria.threshold
            guard target > 0, criteria.direction != .either else { return nil }
            let reached = criteria.direction == .up ? price >= target : price <= target
            return Reading(reference: target, direction: reached ? criteria.direction : nil,
                           magnitude: abs(price - target))
        }

        guard let reference = criteria.referencePrice ?? quote.previousClose, reference > 0 else { return nil }
        let delta = price - reference
        let absolute = abs(delta)
        let meetsThreshold = criteria.metric == .percent
            ? absolute * 100 >= criteria.threshold * reference
            : absolute >= criteria.threshold
        let direction: Direction = delta > 0 ? .up : .down
        let matches = delta != 0 && meetsThreshold && (criteria.direction == .either || criteria.direction == direction)
        return Reading(reference: reference, direction: matches ? direction : nil,
                       magnitude: criteria.metric == .percent ? absolute * 100 / reference : absolute)
    }

    func shouldNotify(_ reading: Reading) -> Bool {
        reading.direction != nil && (lastDirection != reading.direction || lastReference != reading.reference)
    }

    mutating func accept(_ reading: Reading, triggeredAt: Date? = nil) {
        lastDirection = reading.direction
        lastReference = reading.reference
        if let triggeredAt { lastTriggeredAt = triggeredAt }
    }

    static func numberText(_ value: Decimal) -> String {
        value.formatted(.number.locale(Locale(identifier: "en_US_POSIX"))
            .precision(.fractionLength(0...8)).grouping(.never))
    }
}
