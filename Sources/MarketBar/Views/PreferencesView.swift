import SwiftUI

struct PreferencesView: View {
    @Bindable var store: MarketStore

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    pageHeader
                    switch store.settingsTab {
                    case .display: DisplayPreferences(store: store)
                    case .updates: UpdatePreferences(store: store)
                    case .alerts: PriceAlertsView(store: store)
                    case .watchlist: WatchlistPreferences(store: store)
                    case .positions: PositionsPreferences(store: store)
                    }
                }
                .padding(23)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .id(store.settingsTab)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 690, minHeight: 500)
        .sheet(item: $store.tradeRequest) { request in
            PositionTradeSheet(store: store, id: request.instrumentID, side: request.side)
        }
    }

    private var pageHeader: some View {
        HStack(spacing: 13) {
            MarketGlyph(symbol: store.settingsTab.icon, tint: MarketAppearance.gold, size: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(store.settingsTab.title)
                    .font(.system(size: 25, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(store.settingsTab.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 3)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 9) {
                MarketGlyph(symbol: "chart.line.uptrend.xyaxis", tint: MarketAppearance.gold, size: 35)
                Text("行情栏").font(.system(size: 15, weight: .semibold))
            }
            .padding(.horizontal, 7)
            .padding(.bottom, 17)
            ForEach([MarketStore.SettingsTab.display, .updates, .alerts, .watchlist, .positions], id: \.self) { tab in
                SettingsNavRow(tab: tab, selected: store.settingsTab == tab) { store.settingsTab = tab }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13)
        .padding(.top, 23)
        .frame(width: 165)
        .background(.regularMaterial)
    }
}

private struct SettingsNavRow: View {
    let tab: MarketStore.SettingsTab
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: tab.icon).font(.system(size: 13, weight: .medium))
                    .frame(width: 20)
                    .accessibilityHidden(true)
                Text(tab.title).font(.system(size: 13, weight: selected ? .semibold : .medium))
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(selected ? Color.accentColor : .primary)
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(selected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(hovering ? 0.06 : 0),
                        in: RoundedRectangle(cornerRadius: 9))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private extension MarketStore.SettingsTab {
    var title: String {
        switch self {
        case .display: "菜单栏"
        case .updates: "更新与通知"
        case .alerts: "价格提醒"
        case .watchlist: "自选"
        case .positions: "持仓"
        }
    }

    var icon: String {
        switch self {
        case .display: "menubar.rectangle"
        case .updates: "clock"
        case .alerts: "bell.badge"
        case .watchlist: "star"
        case .positions: "briefcase"
        }
    }

    var detail: String {
        switch self {
        case .display: "选择顶部菜单栏显示的行情。"
        case .updates: "设置行情刷新频率和定时报价。"
        case .alerts: "为自选品种设置涨跌阈值。"
        case .watchlist: "添加要关注的股票和 ETF。"
        case .positions: "查看仓位、成本与交易记录。"
        }
    }
}

private struct DisplayPreferences: View {
    @Bindable var store: MarketStore

    var body: some View {
        SettingsCard(title: "菜单栏预览") {
            HStack {
                Spacer()
                MenuBarPriceLabel(quote: store.menuBarQuote, isPreview: true)
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .textSelection(.enabled)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(.primary.opacity(0.08), in: Capsule())
                Spacer()
            }
            .padding(.vertical, 8)
            .background(MarketAppearance.gold.opacity(0.085), in: RoundedRectangle(cornerRadius: 11))
        }
        SettingsCard(title: "显示选项") {
            SettingsOptionRow(title: "显示方式") {
                SettingsSegments(title: "显示方式", values: Preferences.DisplayMode.allCases,
                                 selection: $store.preferences.displayMode, label: { $0.label })
            }
            if store.preferences.displayMode == .fixed {
                SettingsOptionRow(title: "固定品种") {
                    SettingsSelect(title: "固定品种", values: store.allIDs,
                                   selection: $store.preferences.pinnedID, label: store.name(for:))
                }
            } else {
                IntervalField("每项停留", value: $store.preferences.rotationSeconds,
                              range: Preferences.rotationRange, unit: "秒")
            }
            SettingsOptionRow(title: "显示内容") {
                SettingsSelect(title: "显示内容", values: Preferences.LabelStyle.allCases,
                               selection: $store.preferences.labelStyle, label: { $0.label })
            }
            SettingsOptionRow(title: "显示涨跌幅") {
                Toggle("显示涨跌幅", isOn: $store.preferences.showChange).labelsHidden().toggleStyle(.switch)
            }
        }
        if store.preferences.displayMode == .rotation {
            SettingsCard(title: "轮播品种") {
                ForEach(store.allIDs, id: \.self) { id in
                    SettingsOptionRow(title: store.name(for: id)) {
                        Toggle(store.name(for: id), isOn: Binding(
                            get: { !store.preferences.excludedFromRotation.contains(id) },
                            set: { included in
                                if included { store.preferences.excludedFromRotation.remove(id) }
                                else { store.preferences.excludedFromRotation.insert(id) }
                            }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }
                }
                Text("全部取消时，菜单栏会显示浙商积存金。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct UpdatePreferences: View {
    @Bindable var store: MarketStore

    var body: some View {
        SettingsCard(title: "行情刷新") {
            IntervalField("刷新间隔", value: $store.preferences.refreshMinutes,
                          range: Preferences.refreshRange, unit: "分钟")
            Text("报价时间使用北京时间。休市时可能显示上一笔报价。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        SettingsCard(title: "定时报价") {
            SettingsOptionRow(title: "发送定时通知", detail: "应用运行且 Mac 醒着时发送。") {
                Toggle("发送定时通知", isOn: Binding(
                    get: { store.preferences.notificationEnabled },
                    set: { value in Task { await store.setNotifications(value) } }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(store.checkingNotifications)
            }
            IntervalField("通知间隔", value: $store.preferences.notificationMinutes,
                          range: Preferences.notificationRange, unit: "分钟")
            SettingsOptionRow(title: "通知内容") {
                SettingsSelect(title: "通知内容", values: Preferences.NotificationScope.allCases,
                               selection: $store.preferences.notificationScope, label: { $0.label })
            }
            Button("发送测试通知") { Task { await store.sendNotification() } }
                .disabled(!store.preferences.notificationEnabled || store.checkingNotifications)
            if let message = store.notificationMessage {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct WatchlistPreferences: View {
    let store: MarketStore
    @State private var input = ""
    @State private var error: String?

    var body: some View {
        SettingsCard(title: "添加股票或 ETF") {
            HStack(spacing: 10) {
                SettingsTextField(title: "股票代码", text: $input, prompt: "600519、159934、00700、AAPL")
                    .onSubmit(add)
                Button(store.addingStock ? "查询中…" : "添加", action: add)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!canAdd)
            }
            Text("支持沪深京、港股和美股。可写市场前缀，例如 sh600519、hk00700、usAAPL。")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let error {
                Label(error, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange)
            }
        }
        SettingsCard(title: "已订阅 · \(store.preferences.stockIDs.count)/\(MarketStore.stockLimit)") {
            if store.preferences.stockIDs.isEmpty {
                Text("还没有添加股票。").foregroundStyle(.secondary)
            }
            ForEach(store.preferences.stockIDs, id: \.self) { id in
                HStack(spacing: 11) {
                    MarketGlyph(symbol: "chart.line.uptrend.xyaxis", size: 29)
                    Text(store.name(for: id)).lineLimit(1)
                    Spacer()
                    Text(Instrument(id)?.code ?? id)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                    MarketIconButton(label: "移除 \(store.name(for: id))", symbol: "minus") {
                        store.removeStock(id)
                    }
                }
            }
        }
    }

    private var canAdd: Bool {
        !store.addingStock && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func add() {
        guard canAdd else { return }
        let submitted = input
        error = nil
        Task {
            error = await store.addStock(submitted)
            if error == nil, input == submitted { input = "" }
        }
    }
}

private struct IntervalField: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let unit: String

    init(_ label: String, value: Binding<Int>, range: ClosedRange<Int>, unit: String) {
        self.label = label
        _value = value
        self.range = range
        self.unit = unit
    }

    var body: some View {
        SettingsOptionRow(title: label) {
            HStack(spacing: 6) {
                MarketIconButton(label: "减少\(label)", symbol: "minus") { value -= 1 }
                    .disabled(value <= range.lowerBound)
                TextField(label, value: Binding(
                    get: { value },
                    set: { value = min(max($0, range.lowerBound), range.upperBound) }
                ), format: .number.grouping(.never))
                .labelsHidden()
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .monospacedDigit()
                .frame(width: 48, height: 30)
                .background(.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 7))
                MarketIconButton(label: "增加\(label)", symbol: "plus") { value += 1 }
                    .disabled(value >= range.upperBound)
                Text(unit).font(.caption).foregroundStyle(.secondary).frame(width: 26, alignment: .trailing)
            }
        }
    }
}
