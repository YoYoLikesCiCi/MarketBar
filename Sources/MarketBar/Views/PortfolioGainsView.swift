import SwiftUI

struct PortfolioGainsView: View {
    let gains: [PortfolioGain]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "chart.bar.xaxis").foregroundStyle(.secondary)
                Text("总盈亏").fontWeight(.semibold).accessibilityAddTraits(.isHeader)
                Spacer()
                Text("浮动 + 已实现").foregroundStyle(.secondary)
            }
            .font(.caption)

            ForEach(gains) { gain in
                HStack {
                    Text(gain.currency)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                    Spacer()
                    if gain.isPartial {
                        Text(gain.total == nil ? "缺成本或报价" : "已知部分")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    if gain.usesCachedQuotes {
                        Text("含缓存报价").font(.caption2).foregroundStyle(.secondary)
                    }
                    Text(money(gain.total, currency: gain.currency))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(tint(for: gain.total))
                }
                .accessibilityElement(children: .combine)
                .help("浮动 \(money(gain.unrealized.value, currency: gain.currency)) · 已实现 \(money(gain.realized.value, currency: gain.currency))")
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 11))
    }

    private func money(_ amount: Decimal?, currency: String) -> String {
        guard let amount else { return "—" }
        let sign = amount < 0 ? "−" : (amount > 0 ? "+" : "")
        return sign + Quote.currencySymbol(for: currency) + abs(amount).formatted(.number.precision(.fractionLength(2)))
    }

    private func tint(for amount: Decimal?) -> Color {
        guard let amount, amount != 0 else { return .secondary }
        return amount > 0 ? .red : .green
    }
}
