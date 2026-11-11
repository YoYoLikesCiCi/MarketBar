import Foundation

struct PortfolioGain: Identifiable {
    struct Component {
        private(set) var subtotal: Decimal = 0
        private(set) var knownCount = 0
        private(set) var unknownCount = 0

        var value: Decimal? { knownCount == 0 && unknownCount > 0 ? nil : subtotal }

        mutating func include(_ gain: Decimal?) {
            if let gain {
                subtotal += gain
                knownCount += 1
            } else {
                unknownCount += 1
            }
        }
    }

    let currency: String
    var id: String { currency }
    private(set) var unrealized = Component()
    private(set) var realized = Component()
    private(set) var usesCachedQuotes = false

    var total: Decimal? {
        guard unrealized.knownCount + realized.knownCount > 0 else { return nil }
        return unrealized.subtotal + realized.subtotal
    }

    var isPartial: Bool { unrealized.unknownCount + realized.unknownCount > 0 }

    static func summarize(book: PositionBook, quotes: [String: Quote], staleIDs: Set<String>) -> [Self] {
        var summaries: [String: Self] = [:]
        for (id, position) in book.positions where (position.quantity ?? 0) > 0 {
            guard let currency = currency(for: id) else { continue }
            let gain = position.valuation(at: quotes[id]?.price)?.gain
            summaries[currency, default: Self(currency: currency)].unrealized.include(gain)
            if gain != nil && staleIDs.contains(id) {
                summaries[currency]?.usesCachedQuotes = true
            }
        }

        for (id, trades) in book.trades {
            guard let currency = currency(for: id) else { continue }
            for trade in trades where trade.side == .sell {
                summaries[currency, default: Self(currency: currency)].realized.include(trade.realizedGain)
            }
        }

        return summaries.values.sorted {
            if $0.currency == "CNY" { return $1.currency != "CNY" }
            if $1.currency == "CNY" { return false }
            return $0.currency < $1.currency
        }
    }

    private static func currency(for id: String) -> String? {
        id == Instrument.goldID ? "CNY" : Instrument(id)?.currency
    }
}
