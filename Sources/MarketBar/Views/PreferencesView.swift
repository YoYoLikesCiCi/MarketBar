import SwiftUI

struct PreferencesView: View {
    @Bindable var store: MarketStore

    var body: some View {
        TabView(selection: $store.settingsTab) {
            DisplayPreferences(store: store)
                .tabItem { Label("菜单栏", systemImage: "menubar.rectangle") }
                .tag(MarketStore.SettingsTab.display)
            UpdatePreferences(store: store)
                .tabItem { Label("更新与通知", systemImage: "bell") }
                .tag(MarketStore.SettingsTab.updates)
            WatchlistPreferences(store: store)
                .tabItem { Label("自选股", systemImage: "list.star") }
                .tag(MarketStore.SettingsTab.watchlist)
            PositionsPreferences(store: store)
                .tabItem { Label("持仓", systemImage: "briefcase") }
                .tag(MarketStore.SettingsTab.positions)
        }
        .frame(width: 500, height: 420)
    }
}

private struct DisplayPreferences: View {
    @Bindable var store: MarketStore

    var body: some View {
        Form {
            Section("顶部菜单栏") {
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
                LabeledContent("当前预览") {
                    Text(store.menuBarTitle)
                        .monospacedDigit()
                        .textSelection(.enabled)
                }
            }
            if store.preferences.displayMode == .rotation {
                Section("轮播品种") {
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
        .formStyle(.grouped)
    }
}

private struct UpdatePreferences: View {
    @Bindable var store: MarketStore

    var body: some View {
        Form {
            Section("行情刷新") {
                IntervalField("刷新间隔", value: $store.preferences.refreshMinutes,
                              range: Preferences.refreshRange, unit: "分钟")
                Text("报价时间统一为北京时间。休市时，接口可能继续返回上一笔报价。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("定时通知") {
                Toggle("发送行情通知", isOn: Binding(
                    get: { store.preferences.notificationEnabled },
                    set: { value in Task { await store.setNotifications(value) } }
                ))
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
        .formStyle(.grouped)
    }
}

private struct WatchlistPreferences: View {
    let store: MarketStore
    @State private var input = ""
    @State private var error: String?
    @FocusState private var inputFocused: Bool

    var body: some View {
        Form {
            Section("添加股票或 ETF") {
                HStack {
                    TextField("股票代码", text: $input, prompt: Text("600519、159934、00700、AAPL"))
                        .labelsHidden()
                        .focused($inputFocused)
                        .onSubmit(add)
                        .accessibilityLabel("股票代码")
                    Button(store.addingStock ? "查询中…" : "添加", action: add)
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
            Section("已订阅 · \(store.preferences.stockIDs.count)/\(MarketStore.stockLimit)") {
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
        .formStyle(.grouped)
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
