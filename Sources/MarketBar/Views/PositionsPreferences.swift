import SwiftUI

struct PositionsPreferences: View {
    @Bindable var store: MarketStore

    var body: some View {
        SettingsCard(title: "持仓品种") {
            Picker("品种", selection: $store.positionID) {
                ForEach(store.allIDs, id: \.self) { id in
                    Text(store.name(for: id)).tag(id)
                }
            }
        }
        PositionEditor(store: store, id: store.positionID)
            .id(store.positionID)
    }
}

private struct PositionEditor: View {
    let store: MarketStore
    let id: String
    @State private var quantity: String
    @State private var unitCost: String
    @State private var error: String?
    @State private var saved = false
    @State private var showingUndo = false

    init(store: MarketStore, id: String) {
        self.store = store
        self.id = id
        let position = store.positions[id]
        _quantity = State(initialValue: position?.quantityText ?? "")
        _unitCost = State(initialValue: position?.unitCostText ?? "")
    }

    private var isGold: Bool { id == Instrument.goldID }
    private var unit: String { isGold ? "克" : "股或份" }
    private var currency: String { Instrument(id)?.currency ?? "CNY" }
    private var isEdited: Bool {
        let position = store.positions[id]
        return quantity != (position?.quantityText ?? "") || unitCost != (position?.unitCostText ?? "")
    }

    var body: some View {
        SettingsCard(title: "当前持仓") {
            if let position = store.positions[id] {
                PositionMetrics(position: position, quote: store.quotes[id], id: id)
            } else {
                Text("暂无持仓").foregroundStyle(.secondary)
            }
            HStack {
                Button { openTrade(.buy) } label: { Label("加仓", systemImage: "plus") }
                    .buttonStyle(.borderedProminent)
                Button { openTrade(.sell) } label: { Label("减持", systemImage: "minus") }
                    .disabled((store.positions[id]?.quantity ?? 0) <= 0)
            }
            .disabled(isEdited)
            if isEdited {
                Text("保存手工调整后即可登记交易。").font(.caption).foregroundStyle(.secondary)
            }
        }

        SettingsCard(title: "手工调整") {
            field("持仓份额", text: $quantity, suffix: unit)
            field("成本价", text: $unitCost, suffix: "\(currency)/\(unit)")

            Text(isGold ? "填入每克平均成本。清空两项并保存可移除持仓。"
                        : "填入每股或每份的平均成本。清空两项并保存可移除持仓。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("保存调整", action: save).disabled(!isEdited)
                    .buttonStyle(.bordered)
                if saved && !isEdited {
                    Label("已保存", systemImage: "checkmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let error {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .onChange(of: [quantity, unitCost]) { error = nil }
        .onChange(of: store.positions[id]) { _, position in
            quantity = position?.quantityText ?? ""
            unitCost = position?.unitCostText ?? ""
        }

        let trades = store.trades(for: id)
        if !trades.isEmpty {
            SettingsCard(title: "加仓与减持记录") {
                ForEach(trades.reversed()) { trade in
                    PositionTradeRow(trade: trade, unit: unit, currency: currency)
                    Divider()
                }
                Button("撤销最近一笔…") { showingUndo = true }
                    .disabled(isEdited || !store.canUndoTrade(for: id))
                    .confirmationDialog("撤销最近一笔操作？", isPresented: $showingUndo) {
                        Button("撤销", role: .destructive) { undo() }
                        Button("取消", role: .cancel) {}
                    } message: {
                        Text("持仓会恢复到这笔操作之前。")
                    }
            }
        }
    }

    private func field(_ label: String, text: Binding<String>, suffix: String) -> some View {
        HStack(spacing: 8) {
            Text(label).accessibilityHidden(true)
            Spacer()
            TextField(label, text: text, prompt: Text("选填"))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 135)
                .accessibilityLabel(label)
                .onSubmit { if isEdited { save() } }
            Text(suffix)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
        }
    }

    private func openTrade(_ side: PositionTrade.Side) {
        store.tradeRequest = PositionTradeRequest(instrumentID: id, side: side)
    }

    private func save() {
        do {
            let position = try Position(quantityText: quantity, unitCostText: unitCost)
            try store.savePosition(position, for: id)
            quantity = position.quantityText
            unitCost = position.unitCostText
            error = nil
            saved = true
        } catch {
            self.error = error.localizedDescription
            saved = false
        }
    }

    private func undo() {
        do {
            try store.undoTrade(for: id)
            saved = false
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
