import SwiftUI

struct PositionsPreferences: View {
    @Bindable var store: MarketStore
    @State private var tradeSide: PositionTrade.Side?

    var body: some View {
        Form {
            Picker("品种", selection: $store.positionID) {
                ForEach(store.allIDs, id: \.self) { id in
                    Text(store.name(for: id)).tag(id)
                }
            }

            PositionEditor(store: store, id: store.positionID, tradeSide: $tradeSide)
                .id(store.positionID)
        }
        .formStyle(.grouped)
        .sheet(item: $tradeSide) { side in
            PositionTradeSheet(store: store, id: store.positionID, side: side)
        }
    }
}

private struct PositionEditor: View {
    let store: MarketStore
    let id: String
    @Binding var tradeSide: PositionTrade.Side?
    @State private var quantity: String
    @State private var unitCost: String
    @State private var error: String?
    @State private var saved = false
    @State private var showingUndo = false

    init(store: MarketStore, id: String, tradeSide: Binding<PositionTrade.Side?>) {
        self.store = store
        self.id = id
        _tradeSide = tradeSide
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
        Section("持仓信息") {
            HStack {
                Button("加仓") { tradeSide = .buy }
                    .disabled(isEdited)
                Button("减持") { tradeSide = .sell }
                    .disabled(isEdited || (store.positions[id]?.quantity ?? 0) <= 0)
            }

            field("持仓份额", text: $quantity, suffix: unit)
            field("成本价", text: $unitCost, suffix: "\(currency)/\(unit)")

            Text(isGold ? "填入每克平均成本。清空两项并保存可移除持仓。"
                        : "填入每股或每份的平均成本。清空两项并保存可移除持仓。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("保存调整", action: save).disabled(!isEdited)
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
            Section("加仓与减持记录") {
                ForEach(trades.reversed()) { trade in
                    PositionTradeRow(trade: trade, unit: unit, currency: currency)
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
        LabeledContent(label) {
            HStack {
                TextField(label, text: text, prompt: Text("选填"))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 135)
                    .accessibilityLabel(label)
                    .onSubmit { if isEdited { save() } }
                Text(suffix)
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .leading)
            }
        }
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
