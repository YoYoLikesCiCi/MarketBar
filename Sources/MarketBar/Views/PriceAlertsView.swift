import SwiftUI
import UserNotifications

struct PriceAlertsView: View {
    let store: MarketStore
    @State private var editor: Editor?
    @State private var pendingRemoval: PriceAlertRule?

    private enum Editor: Identifiable {
        case new(String), edit(PriceAlertRule)
        var id: String {
            switch self {
            case .new(let id): "new-\(id)"
            case .edit(let rule): rule.id.uuidString
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !store.priceAlerts.canNotify { permissionCard }
            HStack {
                Text("监测规则").font(.system(size: 16, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button {
                    let selected = store.alertInstrumentID ?? store.displayedID
                    editor = .new(store.allIDs.contains(selected) ? selected : Instrument.goldID)
                } label: {
                    Label("新增规则", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            if store.priceAlerts.rules.isEmpty {
                SettingsCard(title: "还没有价格提醒") {
                    Text("例如：浙商积存金涨到 950 元/克时提醒。")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(store.priceAlerts.rules) { rule in
                    ruleCard(rule)
                }
                Text("每次刷新行情时检查。持续越过同一阈值只提醒一次，回到范围内后可再次触发。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let message = store.priceAlerts.message {
                Label(message, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .task { await store.priceAlerts.updateAuthorization() }
        .sheet(item: $editor) { mode in
            switch mode {
            case .new(let id): PriceAlertEditor(store: store, instrumentID: id)
            case .edit(let rule): PriceAlertEditor(store: store, instrumentID: rule.criteria.instrumentID, rule: rule)
            }
        }
        .alert("删除价格提醒？", isPresented: Binding(
            get: { pendingRemoval != nil },
            set: { if !$0 { pendingRemoval = nil } }
        ), presenting: pendingRemoval) { rule in
            Button("删除", role: .destructive) { store.priceAlerts.remove(id: rule.id) }
            Button("取消", role: .cancel) {}
        } message: { rule in
            Text("\(store.name(for: rule.criteria.instrumentID)) · \(rule.criteria.summary)")
        }
    }

    private var permissionCard: some View {
        SettingsCard(title: "系统通知") {
            if store.priceAlerts.authorization == .denied {
                Label("请在「系统设置 → 通知 → 行情栏」打开通知。", systemImage: "bell.slash")
                    .foregroundStyle(.secondary)
                Button("重新检查") { Task { await store.priceAlerts.updateAuthorization() } }
            } else if store.priceAlerts.authorization == nil {
                Text("正在检查通知权限…").foregroundStyle(.secondary)
            } else {
                HStack {
                    Text("允许通知后，达到阈值时会收到提醒。")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("允许通知") { Task { await store.priceAlerts.requestPermission() } }
                        .disabled(store.priceAlerts.requestingPermission)
                }
            }
        }
    }

    private func ruleCard(_ rule: PriceAlertRule) -> some View {
        let id = rule.criteria.instrumentID
        let tracked = store.allIDs.contains(id)
        return HStack(spacing: 12) {
            MarketGlyph(symbol: "bell.badge", tint: id == Instrument.goldID ? MarketAppearance.gold : .accentColor)
            VStack(alignment: .leading, spacing: 5) {
                Text(store.name(for: id)).font(.system(size: 14, weight: .semibold))
                Text(rule.criteria.summary).font(.subheadline).foregroundStyle(.secondary)
                if !tracked {
                    Text("已移出自选，重新添加后恢复监测").font(.caption).foregroundStyle(.orange)
                } else if let date = rule.lastTriggeredAt {
                    Text("上次提醒 \(Quote.displayTime(date))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            Toggle("启用提醒", isOn: Binding(
                get: { rule.enabled },
                set: { store.priceAlerts.setEnabled($0, id: rule.id) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .help(rule.enabled ? "暂停提醒" : "启用提醒")
            MarketIconButton(label: "编辑规则", symbol: "pencil") { editor = .edit(rule) }
            MarketIconButton(label: "删除规则", symbol: "trash") { pendingRemoval = rule }
        }
        .padding(14)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 13))
    }
}

private struct PriceAlertEditor: View {
    private enum Reference: CaseIterable {
        case previousClose, custom
        var label: String { self == .previousClose ? "昨收" : "自定价格" }
    }

    let store: MarketStore
    let ruleID: UUID?
    @Environment(\.dismiss) private var dismiss
    @State private var instrumentID: String
    @State private var metric: PriceAlertRule.Metric
    @State private var direction: PriceAlertRule.Direction
    @State private var reference: Reference
    @State private var threshold: String
    @State private var targetPrice: String
    @State private var referencePrice: String
    @State private var error: String?

    init(store: MarketStore, instrumentID: String, rule: PriceAlertRule? = nil) {
        self.store = store
        ruleID = rule?.id
        _instrumentID = State(initialValue: instrumentID)
        let criteria = rule?.criteria
        let value = criteria.map { PriceAlertRule.numberText($0.threshold) } ?? ""
        let targetsPrice = criteria?.metric == .targetPrice
        _metric = State(initialValue: criteria?.metric ?? .targetPrice)
        _direction = State(initialValue: criteria?.direction ?? .up)
        _reference = State(initialValue: rule?.criteria.referencePrice == nil ? .previousClose : .custom)
        _threshold = State(initialValue: targetsPrice ? "" : value)
        _targetPrice = State(initialValue: targetsPrice ? value : "")
        _referencePrice = State(initialValue: rule?.criteria.referencePrice.map(PriceAlertRule.numberText) ?? "")
    }

    private var priceUnit: String {
        instrumentID == Instrument.goldID ? "元/克" : (Instrument(instrumentID)?.currency ?? "CNY") + "/单位"
    }

    private var targetsPrice: Bool { metric == .targetPrice }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 10) {
                MarketGlyph(symbol: "bell.badge", tint: MarketAppearance.gold, size: 40)
                Text(ruleID == nil ? "新增价格提醒" : "编辑价格提醒")
                    .font(.system(size: 20, weight: .semibold))
            }

            SettingsCard(title: "触发条件") {
                SettingsOptionRow(title: "品种") {
                    SettingsSelect(title: "品种", values: store.allIDs, selection: $instrumentID,
                                   label: store.name(for:))
                }
                SettingsOptionRow(title: "比较方式") {
                    SettingsSegments(title: "比较方式", values: PriceAlertRule.Metric.allCases,
                                     selection: $metric, label: { $0.label })
                }
                if targetsPrice {
                    SettingsOptionRow(title: "触发方向") {
                        SettingsSegments(title: "触发方向", values: [.up, .down], selection: $direction,
                                         label: { $0 == .up ? "涨到或高于" : "跌到或低于" })
                    }
                    SettingsOptionRow(title: "目标价格") {
                        SettingsTextField(title: "目标价格", text: $targetPrice, prompt: "输入价格",
                                          unit: priceUnit, numeric: true)
                        .frame(width: 145)
                    }
                } else {
                    relativeCondition
                }
            }

            if let error {
                Label(error, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存规则", action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onChange(of: metric) {
            error = nil
            if targetsPrice && direction == .either { direction = .up }
        }
    }

    private var relativeCondition: some View {
        VStack(spacing: 12) {
            SettingsOptionRow(title: "参考价格") {
                SettingsSegments(title: "参考价格", values: Reference.allCases,
                                 selection: $reference, label: { $0.label })
            }
            if reference == .custom {
                SettingsOptionRow(title: "自定参考价") {
                    SettingsTextField(title: "自定参考价", text: $referencePrice, prompt: "例如 900",
                                      unit: priceUnit, numeric: true)
                    .frame(width: 145)
                }
            }
            SettingsOptionRow(title: "变动方向") {
                SettingsSegments(title: "变动方向", values: PriceAlertRule.Direction.allCases,
                                 selection: $direction, label: { $0.label })
            }
            SettingsOptionRow(title: "达到或超过") {
                SettingsTextField(title: "达到或超过", text: $threshold, prompt: "例如 3",
                                  unit: metric == .percent ? "%" : priceUnit, numeric: true)
                .frame(width: 145)
            }
        }
    }

    private func save() {
        guard store.allIDs.contains(instrumentID) else {
            error = "请选择一个自选品种。"
            return
        }
        guard let value = positive(targetsPrice ? targetPrice : threshold) else {
            error = targetsPrice ? "请输入大于 0 的目标价格，最多 8 位小数。"
                                 : "请输入大于 0 的阈值，最多 8 位小数。"
            return
        }
        let usesCustomReference = !targetsPrice && reference == .custom
        let base = usesCustomReference ? positive(referencePrice) : nil
        guard !usesCustomReference || base != nil else {
            error = "请输入大于 0 的参考价格，最多 8 位小数。"
            return
        }

        store.priceAlerts.save(id: ruleID, criteria: .init(instrumentID: instrumentID, metric: metric,
                                direction: direction, threshold: value, referencePrice: base))
        dismiss()
        Task {
            await store.priceAlerts.updateAuthorization()
            if store.priceAlerts.authorization == .notDetermined {
                await store.priceAlerts.requestPermission()
            }
        }
    }

    private func positive(_ text: String) -> Decimal? {
        guard let number = try? Position.parse(text, error: .unitCost), number > 0 else { return nil }
        return number
    }
}
