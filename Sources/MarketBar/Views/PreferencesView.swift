import SwiftUI

struct PreferencesView: View {
    @Bindable var store: MarketStore

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                Text(store.settingsTab.title)
                    .font(.system(size: 24, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, 22)
                    .padding(.top, 20)
                    .padding(.bottom, 12)

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        switch store.settingsTab {
                        case .display: DisplayPreferences(store: store)
                        case .updates: UpdatePreferences(store: store)
                        case .watchlist: WatchlistPreferences(store: store)
                        case .positions: PositionsPreferences(store: store)
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .id(store.settingsTab)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 635, minHeight: 475)
        .sheet(item: $store.tradeRequest) { request in
            PositionTradeSheet(store: store, id: request.instrumentID, side: request.side)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 9) {
                MarketGlyph(symbol: "chart.line.uptrend.xyaxis", tint: MarketAppearance.gold, size: 29)
                Text("行情栏").font(.headline)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 15)
            ForEach([MarketStore.SettingsTab.display, .updates, .watchlist, .positions], id: \.self) { tab in
                Button {
                    store.settingsTab = tab
                } label: {
                    Label(tab.title, systemImage: tab.icon)
                        .font(.system(size: 13, weight: store.settingsTab == tab ? .semibold : .regular))
                        .foregroundStyle(store.settingsTab == tab ? Color.accentColor : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 8)
                        .background(Color.accentColor.opacity(store.settingsTab == tab ? 0.13 : 0),
                                    in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(store.settingsTab == tab ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11)
        .padding(.top, 20)
        .frame(width: 148)
        .background(.regularMaterial)
    }
}

private extension MarketStore.SettingsTab {
    var title: String {
        switch self {
        case .display: "菜单栏"
        case .updates: "更新与通知"
        case .watchlist: "自选"
        case .positions: "持仓"
        }
    }

    var icon: String {
        switch self {
        case .display: "menubar.rectangle"
        case .updates: "bell"
        case .watchlist: "list.star"
        case .positions: "briefcase"
        }
    }
}

private struct DisplayPreferences: View {
    @Bindable var store: MarketStore

    var body: some View {
        VStack(spacing: 12) {
            SettingsCard(title: "显示方式") {
                Picker("显示方式", selection: $store.preferences.displayMode) {
                    ForEach(Preferences.DisplayMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                if store.preferences.displayMode == .fixed {
                    Picker("固定品种", selection: $store.preferences.pinnedID) {
                        ForEach(store.allIDs, id: \.self) { id in Text(store.name(for: id)).tag(id) }
                    }
                } else {
                    IntervalField("每项停留", value: $store.preferences.rotationSeconds,
                                  range: Preferences.rotationRange, unit: "秒")
                }
                Picker("显示内容", selection: $store.preferences.labelStyle) {
                    ForEach(Preferences.LabelStyle.allCases) { Text($0.label).tag($0) }
                }
                Toggle("显示涨跌幅", isOn: $store.preferences.showChange)
                    .toggleStyle(.switch)
                LabeledContent("当前预览") {
                    Text(store.menuBarTitle)
                        .monospacedDigit()
                        .textSelection(.enabled)
                }
            }
            if store.preferences.displayMode == .rotation {
                SettingsCard(title: "轮播品种") {
                    ForEach(store.allIDs, id: \.self) { id in
                        Toggle(store.name(for: id), isOn: Binding(
                            get: { !store.preferences.excludedFromRotation.contains(id) },
                            set: { included in
                                if included { store.preferences.excludedFromRotation.remove(id) }
                                else { store.preferences.excludedFromRotation.insert(id) }
                            }
                        ))
                    }
                    Text("全部取消时，菜单栏会显示浙商积存金。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct UpdatePreferences: View {
    @Bindable var store: MarketStore

    var body: some View {
        VStack(spacing: 12) {
            SettingsCard(title: "行情刷新") {
                IntervalField("刷新间隔", value: $store.preferences.refreshMinutes,
                              range: Preferences.refreshRange, unit: "分钟")
                Text("报价时间统一为北京时间。休市时，接口可能继续返回上一笔报价。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            SettingsCard(title: "定时通知") {
                Toggle("发送行情通知", isOn: Binding(
                    get: { store.preferences.notificationEnabled },
                    set: { value in Task { await store.setNotifications(value) } }
                ))
                .toggleStyle(.switch)
                .disabled(store.checkingNotifications)
                IntervalField("通知间隔", value: $store.preferences.notificationMinutes,
                              range: Preferences.notificationRange, unit: "分钟")
                Picker("通知内容", selection: $store.preferences.notificationScope) {
                    ForEach(Preferences.NotificationScope.allCases) { Text($0.label).tag($0) }
                }
                Button("现在发送一条") {
                    Task { await store.sendNotification() }
                }
                .disabled(!store.preferences.notificationEnabled || store.checkingNotifications)
                if let message = store.notificationMessage {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
                Text("应用运行且 Mac 醒着时发送。到点会优先获取最新可用报价。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct WatchlistPreferences: View {
    let store: MarketStore
    @State private var input = ""
    @State private var error: String?
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 12) {
            SettingsCard(title: "添加股票或 ETF") {
                HStack {
                    TextField("股票代码", text: $input, prompt: Text("600519、159934、00700、AAPL"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .focused($inputFocused)
                        .onSubmit(add)
                        .accessibilityLabel("股票代码")
                    Button(store.addingStock ? "查询中…" : "添加", action: add)
                        .buttonStyle(.borderedProminent)
                        .disabled(!canAdd)
                }
                Text("支持沪深京、港股和美股。可写市场前缀，例如 sh600519、hk00700、usAAPL。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let error {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            SettingsCard(title: "已订阅 · \(store.preferences.stockIDs.count)/\(MarketStore.stockLimit)") {
                if store.preferences.stockIDs.isEmpty {
                    Text("还没有添加股票。").foregroundStyle(.secondary)
                }
                ForEach(store.preferences.stockIDs, id: \.self) { id in
                    HStack {
                        Text(store.name(for: id)).lineLimit(1)
                        Spacer()
                        Text(Instrument(id)?.code ?? id)
                            .foregroundStyle(.secondary)
                            .monospaced()
                        Button {
                            store.removeStock(id)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("移除 \(store.name(for: id))")
                        .accessibilityLabel("移除 \(store.name(for: id))")
                    }
                }
            }
        }
        .onAppear { inputFocused = true }
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
        LabeledContent(label) {
            HStack(spacing: 6) {
                TextField(label, value: Binding(
                    get: { value },
                    set: { value = min(max($0, range.lowerBound), range.upperBound) }
                ), format: .number.grouping(.never))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 56)
                .accessibilityLabel(label)
                Stepper(label, value: $value, in: range)
                    .labelsHidden()
                Text(unit).foregroundStyle(.secondary)
            }
        }
    }
}
