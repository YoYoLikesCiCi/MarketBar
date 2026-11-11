import AppKit
import SwiftUI

struct QuotesPanel: View {
    let store: MarketStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text("行情栏").font(.headline)
                    Text(store.preferences.displayMode == .fixed ? "固定显示" : "轮播中")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if store.refreshing {
                    ProgressView().controlSize(.small).accessibilityLabel("正在更新")
                }
                Button {
                    Task { await store.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise").padding(3)
                }
                .help("立即刷新")
                .accessibilityLabel("立即刷新")
                .disabled(store.refreshing)
            }
            .padding(12)

            Divider()
            if store.allIDs.count <= 5 {
                rows
            } else {
                ScrollView { rows }.frame(height: 340)
            }
            Divider()

            HStack {
                Button {
                    openSettings(.watchlist)
                } label: {
                    Label("添加股票", systemImage: "plus")
                }
                Spacer()
                Button("设置…") { openSettings(.display) }
                    .keyboardShortcut(",", modifiers: .command)
                Button("退出") { NSApp.terminate(nil) }
                    .keyboardShortcut("q", modifiers: .command)
            }
            .padding(10)
        }
        .frame(width: 375)
    }

    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(store.allIDs, id: \.self) { id in
                QuoteRow(id: id, store: store)
                if id != store.allIDs.last { Divider().padding(.horizontal, 12) }
            }
        }
    }

    private func openSettings(_ tab: MarketStore.SettingsTab) {
        store.settingsTab = tab
        openWindow(id: "preferences")
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct QuoteRow: View {
    let id: String
    let store: MarketStore

    private var isGold: Bool { id == Instrument.goldID }

    var body: some View {
        let quote = store.quotes[id]
        let error = store.errors[id]
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(store.name(for: id)).fontWeight(.semibold).lineLimit(1)
                if store.displayedID == id {
                    Image(systemName: store.preferences.displayMode == .fixed ? "pin.fill" : "play.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("正在菜单栏显示")
                }
                Spacer(minLength: 8)
                Text(quote?.formattedPrice(gold: isGold) ?? "—")
                    .font(.system(.body, design: .monospaced).weight(.semibold))
            }

            HStack(alignment: .firstTextBaseline) {
                Text(isGold ? "京东金融" : "\(Instrument(id)?.code ?? id) · 腾讯财经")
                Spacer(minLength: 8)
                if let quote {
                    Text("报价 \(quote.quoteTime)")
                    if let change = quote.formattedChange {
                        Text(change)
                            .monospacedDigit()
                            .foregroundStyle(changeColor(quote.changePercent ?? 0))
                    }
                } else if error == nil {
                    Text("等待报价")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let error {
                Label(quote == nil ? error : "缓存 · \(error)", systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .help(quote.map { "最近拉取 \(Quote.displayTime($0.fetchedAt))（北京时间）" } ?? "尚未拉取报价")
        .contextMenu {
            Button("固定到菜单栏") { store.pin(id) }
        }
    }

    private func changeColor(_ value: Double) -> Color {
        if value == 0 { return .secondary }
        if Instrument(id)?.market == .us { return value > 0 ? .green : .red }
        return value > 0 ? .red : .green
    }
}
