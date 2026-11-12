import SwiftUI

struct QuoteSpotlight: View {
    let id: String
    let store: MarketStore
    let edit: () -> Void
    let trade: (PositionTrade.Side) -> Void

    private var isGold: Bool { id == Instrument.goldID }
    private var tint: Color { isGold ? MarketAppearance.gold : .accentColor }
    private var position: Position? { store.positions[id] }

    var body: some View {
        let quote = store.quotes[id]
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.name(for: id))
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                    Text(source)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if store.errors[id] != nil {
                    Label(quote == nil ? "更新失败" : "缓存", systemImage: "exclamationmark.circle")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text(quote?.formattedPrice(gold: isGold) ?? "—")
                    .font(.system(size: 33, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let quote, let change = quote.formattedChange, let percent = quote.changePercent {
                    let color = MarketAppearance.movementColor(id: id, sign: percent > 0 ? 1 : percent < 0 ? -1 : 0)
                    Text(change)
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(color)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(color.opacity(0.11), in: Capsule())
                }
            }

            if let quote {
                Label("报价 \(quote.quoteTime)", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("最近拉取 \(Quote.displayTime(quote.fetchedAt))（北京时间）")
            } else if store.errors[id] == nil {
                Text("等待报价").font(.caption).foregroundStyle(.secondary)
            }
            if let error = store.errors[id] {
                Text(error).font(.caption).foregroundStyle(.secondary).lineLimit(2).help(error)
            }

            QuoteTrendView(id: id, store: store, tint: tint)
                .id(id)

            if let position {
                Divider()
                PositionMetrics(position: position, quote: quote, id: id)
            }

            HStack(spacing: 7) {
                Button(action: edit) {
                    Label(position == nil ? "录入持仓" : "编辑持仓", systemImage: "square.and.pencil")
                }
                Spacer(minLength: 2)
                Button { trade(.sell) } label: { Label("减持", systemImage: "minus") }
                    .disabled((position?.quantity ?? 0) <= 0)
                Button { trade(.buy) } label: { Label("加仓", systemImage: "plus") }
                    .buttonStyle(.borderedProminent)
            }
            .controlSize(.regular)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 15)
                .fill(tint.opacity(isGold ? 0.10 : 0.07))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 15)
                .strokeBorder(tint.opacity(0.19))
                .allowsHitTesting(false)
        }
    }

    private var source: String {
        isGold ? "京东金融 · CNY/克" : "\(Instrument(id)?.code ?? id) · 腾讯财经"
    }
}
