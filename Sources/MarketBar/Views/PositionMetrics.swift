import SwiftUI

struct PositionMetrics: View {
    let position: Position
    let quote: Quote?
    let id: String

    private var unit: String { id == Instrument.goldID ? "克" : "股或份" }
    private var symbol: String { Quote.currencySymbol(for: quote?.currency ?? Instrument(id)?.currency ?? "CNY") }

    var body: some View {
        let valuation = position.valuation(at: quote?.price)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                metric("持仓份额", position.quantity.map {
                    "\($0.formatted(.number.precision(.fractionLength(0...8)))) \(unit)"
                } ?? "—")
                metric("成本价", position.unitCost.map { "\(money($0, maximumDecimals: 8))/\(unit)" } ?? "—")
            }

            if position.quantity != nil {
                HStack(alignment: .top, spacing: 12) {
                    metric("持仓市值", valuation.map { money($0.marketValue) } ?? "—")
                    metric("浮动盈亏", gainText(valuation), tint: gainColor(valuation?.gain))
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func metric(_ label: String, _ value: String, tint: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).foregroundStyle(.secondary)
            Text(value)
                .monospacedDigit()
                .foregroundStyle(tint)
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func money(_ value: Decimal, maximumDecimals: Int = 2, signed: Bool = false) -> String {
        let sign = value < 0 ? "−" : (signed && value > 0 ? "+" : "")
        return sign + symbol + abs(value).formatted(.number.precision(.fractionLength(2...maximumDecimals)))
    }

    private func gainText(_ valuation: Position.Valuation?) -> String {
        guard let gain = valuation?.gain else { return "—" }
        let amount = money(gain, signed: true)
        guard let percent = valuation?.gainPercent else { return amount }
        let sign = percent > 0 ? "+" : ""
        let change = percent.formatted(.number.precision(.fractionLength(2)))
        return "\(amount) (\(sign)\(change)%)"
    }

    private func gainColor(_ value: Decimal?) -> Color {
        guard let value, value != 0 else { return .primary }
        let risesInGreen = Instrument(id)?.market == .us
        return (value > 0) == risesInGreen ? .green : .red
    }
}
