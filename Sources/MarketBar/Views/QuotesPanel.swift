import AppKit
import SwiftUI

struct QuotesPanel: View {
    private enum Filter: String, CaseIterable, Identifiable {
        case all = "全部"
        case held = "持仓"
        var id: Self { self }
    }

    let store: MarketStore
    @Environment(\.openWindow) private var openWindow
    @State private var selection: String?
    @State private var filter = Filter.all

    private var visibleIDs: [String] {
        filter == .all ? store.allIDs : store.allIDs.filter { (store.positions[$0]?.quantity ?? 0) > 0 }
    }

    private var selectedID: String? {
        if let selection, visibleIDs.contains(selection) { return selection }
        if visibleIDs.contains(store.displayedID) { return store.displayedID }
        return visibleIDs.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            header
            if let selectedID {
                QuoteSpotlight(
                    id: selectedID, store: store,
                    edit: { openPosition(selectedID) },
                    trade: { openPosition(selectedID, side: $0) }
                )
            } else {
                emptyHoldings
            }
            listHeader
            if store.allIDs.count > 1 && !visibleIDs.isEmpty {
                if visibleIDs.count > 4 {
                    ScrollView { watchlist }.frame(height: 196)
                } else {
                    watchlist
                }
            }
        }
        .padding(15)
        .frame(width: 410)
        .onAppear { if selection == nil { selection = store.displayedID } }
    }

    private var header: some View {
        HStack(spacing: 8) {
            MarketGlyph(symbol: "chart.line.uptrend.xyaxis", tint: MarketAppearance.gold)
            Text("行情栏")
                .font(.system(size: 16, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if store.refreshing {
                ProgressView().controlSize(.small).frame(width: 30, height: 30)
                    .accessibilityLabel("正在更新")
            } else {
                MarketIconButton(label: "立即刷新", symbol: "arrow.clockwise") {
                    Task { await store.refresh() }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
            MarketIconButton(label: "设置", symbol: "gearshape") {
                openSettings(.display)
            }
            .keyboardShortcut(",", modifiers: .command)

            Menu {
                if let selectedID {
                    Button("固定到菜单栏") { store.pin(selectedID) }
                    Divider()
                }
                Button("退出行情栏") { NSApp.terminate(nil) }
                    .keyboardShortcut("q", modifiers: .command)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 30, height: 30)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("更多操作")
            .help("更多操作")
        }
    }

    private var listHeader: some View {
        HStack {
            if store.allIDs.count > 1 || filter == .held {
                HStack(spacing: 2) {
                    ForEach(Filter.allCases) { item in
                        Button {
                            filter = item
                        } label: {
                            Text(item.rawValue)
                                .font(.system(size: 12, weight: filter == item ? .semibold : .regular))
                                .foregroundStyle(filter == item ? Color.primary : .secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .background(.primary.opacity(filter == item ? 0.09 : 0),
                                            in: RoundedRectangle(cornerRadius: 6))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(filter == item ? .isSelected : [])
                    }
                }
                .padding(2)
                .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityElement(children: .contain)
                .accessibilityLabel("查看范围")
            } else {
                Text("自选")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                openSettings(.watchlist)
            } label: {
                Label("添加自选", systemImage: "plus")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.accentColor)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 3)
    }

    private var watchlist: some View {
        VStack(spacing: 2) {
            ForEach(visibleIDs, id: \.self) { id in
                WatchQuoteRow(id: id, store: store, selected: id == selectedID) {
                    selection = id
                }
                .contextMenu {
                    Button("编辑持仓") { openPosition(id) }
                    Button("固定到菜单栏") { store.pin(id) }
                }
            }
        }
    }

    private var emptyHoldings: some View {
        ContentUnavailableView {
            Label("暂无持仓", systemImage: "briefcase")
        } actions: {
            Button("录入持仓") { openPosition(store.displayedID) }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    private func openPosition(_ id: String, side: PositionTrade.Side? = nil) {
        store.positionID = id
        openSettings(.positions, trade: side.map { .init(instrumentID: id, side: $0) })
    }

    private func openSettings(_ tab: MarketStore.SettingsTab, trade: PositionTradeRequest? = nil) {
        store.settingsTab = tab
        store.tradeRequest = trade
        openWindow(id: "preferences")
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct WatchQuoteRow: View {
    let id: String
    let store: MarketStore
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    private var isGold: Bool { id == Instrument.goldID }

    var body: some View {
        let quote = store.quotes[id]
        let code = isGold ? "积存金" : (Instrument(id)?.code ?? id)
        let quantity = store.positions[id]?.quantityText ?? ""
        Button(action: action) {
            HStack(spacing: 9) {
                MarketGlyph(symbol: isGold ? "circle.hexagongrid.fill" : "chart.line.uptrend.xyaxis",
                            tint: isGold ? MarketAppearance.gold : .accentColor, size: 27)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(store.name(for: id)).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        if store.displayedID == id {
                            Image(systemName: store.preferences.displayMode == .fixed ? "pin.fill" : "play.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("菜单栏当前品种")
                        }
                    }
                    Text(quantity.isEmpty ? code : "\(code) · 持仓 \(quantity) \(isGold ? "克" : "股或份")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(quote?.formattedPrice(gold: isGold) ?? "—")
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                    if let change = quote?.formattedChange, let value = quote?.changePercent {
                        Text(change)
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(MarketAppearance.movementColor(id: id, sign: value > 0 ? 1 : value < 0 ? -1 : 0))
                    }
                }
                Image(systemName: store.errors[id] == nil ? "chevron.right" : "exclamationmark.circle")
                    .font(.caption2)
                    .foregroundStyle(store.errors[id] == nil ? Color.secondary : Color.orange)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .frame(minHeight: 43)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 9)
                    .fill(selected ? Color.accentColor.opacity(0.13) : Color.primary.opacity(hovering ? 0.06 : 0))
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
