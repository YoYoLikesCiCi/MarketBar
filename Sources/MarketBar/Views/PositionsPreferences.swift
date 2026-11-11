import SwiftUI

struct PositionsPreferences: View {
    @Bindable var store: MarketStore

    var body: some View {
        Form {
            Picker("品种", selection: $store.positionID) {
                ForEach(store.allIDs, id: \.self) { id in
                    Text(store.name(for: id)).tag(id)
                }
            }

            PositionEditor(store: store, id: store.positionID)
                .id(store.positionID)
        }
        .formStyle(.grouped)
    }
}

private struct PositionEditor: View {
    let store: MarketStore
    let id: String
    @State private var quantity: String
    @State private var unitCost: String
    @State private var error: String?
    @State private var saved = false

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
        Section("持仓信息") {
            field("持仓份额", text: $quantity, suffix: unit)
            field("成本价", text: $unitCost, suffix: "\(currency)/\(unit)")

            Text(isGold ? "填入每克平均成本。清空两项并保存可移除持仓。"
                        : "填入每股或每份的平均成本。清空两项并保存可移除持仓。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("保存", action: save).disabled(!isEdited)
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
            store.savePosition(position, for: id)
            quantity = position.quantityText
            unitCost = position.unitCostText
            error = nil
            saved = true
        } catch {
            self.error = error.localizedDescription
            saved = false
        }
    }
}
