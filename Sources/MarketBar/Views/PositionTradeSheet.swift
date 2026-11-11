import SwiftUI

struct PositionTradeSheet: View {
    private enum Field: Hashable { case quantity, price, fee }

    let store: MarketStore
    let id: String
    let side: PositionTrade.Side

    @Environment(\.dismiss) private var dismiss
    @State private var quantity = ""
    @State private var price = ""
    @State private var fee = ""
    @State private var saveError: String?
    @FocusState private var focusedField: Field?

    private var unit: String { id == Instrument.goldID ? "克" : "股或份" }
    private var currency: String { Instrument(id)?.currency ?? "CNY" }
    private var position: Position? { store.positions[id] }

    private var draft: Result<PositionTrade, Error>? {
        guard !quantity.isEmpty && !price.isEmpty else { return nil }
        return Result {
            try PositionTrade(side: side, quantityText: quantity, priceText: price, feeText: fee,
                              position: position)
        }
    }

    var body: some View {
        let draft = draft
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                MarketGlyph(symbol: side == .buy ? "plus" : "minus",
                            tint: id == Instrument.goldID ? MarketAppearance.gold : .accentColor, size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(side.label) · \(store.name(for: id))")
                        .font(.system(size: 18, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text("当前持仓 \(position?.quantityText ?? "0") \(unit)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(18)
            Divider()

            VStack(spacing: 12) {
                SettingsCard(title: "成交信息") {
                    field("成交份额", value: $quantity, unit: unit, field: .quantity)
                    field("成交单价", value: $price, unit: "\(currency)/\(unit)", field: .price)
                    field("手续费", value: $fee, unit: currency, field: .fee, prompt: "选填")
                }

                SettingsCard(title: "成交预览") {
                    preview(draft)
                }

                if let saveError {
                    Label(saveError, systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(18)
            Divider()

            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("确认\(side.label)") {
                    if case .success(let trade) = draft { save(trade) }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(draft.flatMap { try? $0.get() } == nil)
            }
            .padding(18)
        }
        .frame(width: 460)
        .onAppear { focusedField = .quantity }
        .onChange(of: [quantity, price, fee]) { saveError = nil }
    }

    @ViewBuilder
    private func preview(_ draft: Result<PositionTrade, Error>?) -> some View {
        switch draft {
        case .success(let trade):
            LabeledContent("变动后持仓", value: "\(trade.remaining?.quantityText ?? "0") \(unit)")
            if let remaining = trade.remaining {
                let cost = remaining.unitCostText
                LabeledContent("变动后成本价", value: cost.isEmpty ? "成本未知" : "\(cost) \(currency)/\(unit)")
            }
            if side == .sell {
                LabeledContent("本笔已实现盈亏", value: trade.realizedGain.map {
                    $0.formatted(.currency(code: currency))
                } ?? "成本未知")
            }
        case .failure(let error):
            Label(error.localizedDescription, systemImage: "exclamationmark.circle")
                .font(.subheadline)
                .foregroundStyle(.orange)
        case nil:
            Text("输入成交份额和单价后预览。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func field(_ label: String, value: Binding<String>, unit: String, field: Field,
                       prompt: String = "") -> some View {
        HStack(spacing: 8) {
            Text(label).accessibilityHidden(true)
            Spacer()
            TextField(label, text: value, prompt: Text(prompt))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 125)
                .focused($focusedField, equals: field)
                .accessibilityLabel(label)
            Text(unit)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
        }
    }

    private func save(_ trade: PositionTrade) {
        do {
            try store.recordTrade(trade, for: id)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}

struct PositionTradeRow: View {
    let trade: PositionTrade
    let unit: String
    let currency: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(trade.side.label) \(number(trade.quantity)) \(unit)")
                Spacer()
                Text("\(number(trade.unitPrice)) \(currency)/\(unit)")
                    .monospacedDigit()
            }
            Text(Quote.displayTime(trade.recordedAt))
                .font(.caption)
                .foregroundStyle(.secondary)
            if trade.fee > 0 {
                Text("手续费 \(trade.fee.formatted(.currency(code: currency)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if trade.side == .sell {
                let amount = trade.realizedGain.map { $0.formatted(.currency(code: currency)) }
                Text("已实现盈亏 \(amount ?? "—（成本未知）")")
                    .font(.caption)
            }
        }
    }

    private func number(_ value: Decimal) -> String {
        value.formatted(.number.precision(.fractionLength(0...8)))
    }
}
