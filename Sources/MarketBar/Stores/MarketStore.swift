import Foundation
import Observation
import UserNotifications

@MainActor
@Observable
final class MarketStore {
    enum SettingsTab: Hashable { case display, updates, alerts, watchlist, positions }

    static let stockLimit = 24
    private let defaults: UserDefaults
    private let client = QuoteClient()
    private let notificationCenter = UNUserNotificationCenter.current()
    let priceAlerts: PriceAlertStore
    private var refreshTimer: Timer?
    private var rotationTimer: Timer?
    private var notificationTimer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var lastRefreshStarted: Date?
    private var rotationIndex = 0
    private var trendCache: [String: [QuoteTrendPeriod: TrendCacheEntry]] = [:]

    private struct TrendCacheEntry {
        let fetchedAt: Date
        let points: [QuoteTrendPoint]
    }

    private(set) var quotes: [String: Quote] = [:]
    private(set) var errors: [String: String] = [:]
    private var positionBook = PositionBook()
    private(set) var checkingNotifications = false
    private(set) var notificationMessage: String?
    private(set) var addingStock = false
    var settingsTab = SettingsTab.display
    var positionID = Instrument.goldID
    var tradeRequest: PositionTradeRequest?
    var alertInstrumentID: String?

    var preferences: Preferences {
        didSet {
            guard preferences != oldValue else { return }
            defaults.set(try? JSONEncoder().encode(preferences), forKey: "preferences")
            if preferences.refreshMinutes != oldValue.refreshMinutes { scheduleRefresh() }
            if preferences.notificationEnabled != oldValue.notificationEnabled ||
                preferences.notificationMinutes != oldValue.notificationMinutes {
                scheduleNotification()
            }
            if preferences.displayMode != oldValue.displayMode ||
                preferences.excludedFromRotation != oldValue.excludedFromRotation ||
                preferences.rotationSeconds != oldValue.rotationSeconds ||
                preferences.stockIDs != oldValue.stockIDs {
                rotationIndex = 0
                scheduleRotation()
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        priceAlerts = PriceAlertStore(defaults: defaults)
        var saved = defaults.data(forKey: "preferences").flatMap {
            try? JSONDecoder().decode(Preferences.self, from: $0)
        } ?? Preferences()
        saved.normalize()
        preferences = saved
        positionBook = PositionBook.load(book: defaults.data(forKey: "positionBook"),
                                         legacyPositions: defaults.data(forKey: "positions"))
        if let data = defaults.data(forKey: "quotes"),
           let cache = try? JSONDecoder().decode([String: Quote].self, from: data) {
            let ids = Set(saved.stockIDs + [Instrument.goldID])
            quotes = cache.filter { ids.contains($0.key) }
            errors = quotes.mapValues { _ in "上次保存的报价，等待刷新。" }
        }
    }

    var allIDs: [String] { [Instrument.goldID] + preferences.stockIDs }
    var refreshing: Bool { refreshTask != nil }
    var positions: [String: Position] { positionBook.positions }
    var portfolioGains: [PortfolioGain] {
        PortfolioGain.summarize(book: positionBook, quotes: quotes, staleIDs: Set(errors.keys))
    }

    private var rotationIDs: [String] {
        let selected = allIDs.filter { !preferences.excludedFromRotation.contains($0) }
        return selected.isEmpty ? [Instrument.goldID] : selected
    }

    var displayedID: String {
        preferences.displayMode == .fixed ? preferences.pinnedID : rotationIDs[rotationIndex % rotationIDs.count]
    }

    var menuBarQuote: MenuBarQuote {
        let id = displayedID
        let gold = id == Instrument.goldID
        let quote = quotes[id]
        let prefix: String
        switch preferences.labelStyle {
        case .name: prefix = gold ? "浙商金" : String(name(for: id).prefix(8))
        case .code: prefix = gold ? "浙商金" : (Instrument(id)?.code ?? id)
        case .price: prefix = ""
        }
        let price = quote?.formattedPrice(gold: gold) ?? "—"
        let change = preferences.showChange ? quote?.formattedChange : nil
        let suffix = [change, errors[id] == nil ? nil : "⚠︎"]
            .compactMap { $0 }.map { " " + $0 }.joined()
        return MenuBarQuote(id: id, prefix: prefix.isEmpty ? "" : prefix + " ", price: price,
                            suffix: suffix, changePercent: quote?.changePercent)
    }

    func name(for id: String) -> String {
        if id == Instrument.goldID { return "浙商积存金" }
        return quotes[id]?.name ?? Instrument(id)?.code ?? id
    }

    func trend(for id: String, period: QuoteTrendPeriod) async throws -> [QuoteTrendPoint] {
        let now = Date.now
        let calendar = QuoteTrendPoint.calendar(for: id)
        if let cached = trendCache[id]?[period], now.timeIntervalSince(cached.fetchedAt) < 300,
           calendar.isDate(now, equalTo: cached.fetchedAt, toGranularity: period.calendarComponent) {
            return cached.points
        }
        let points = try await client.trend(for: id, period: period)
        try Task.checkCancellation()
        if allIDs.contains(id) {
            trendCache[id, default: [:]][period] = TrendCacheEntry(fetchedAt: .now, points: points)
        }
        return points
    }

    func savePosition(_ position: Position, for id: String) throws {
        guard allIDs.contains(id) else { throw PositionTrade.TradeError.notTracked }
        var updated = positionBook
        updated.positions[id] = position.isEmpty ? nil : position
        try savePositionBook(updated)
    }

    func trades(for id: String) -> [PositionTrade] { positionBook.trades[id] ?? [] }

    func recordTrade(_ trade: PositionTrade, for id: String) throws {
        guard allIDs.contains(id) else { throw PositionTrade.TradeError.notTracked }
        var updated = positionBook
        try updated.record(trade, for: id)
        try savePositionBook(updated)
    }

    func canUndoTrade(for id: String) -> Bool { positionBook.canUndo(for: id) }

    func undoTrade(for id: String) throws {
        guard allIDs.contains(id) else { throw PositionTrade.TradeError.notTracked }
        var updated = positionBook
        try updated.undoLastTrade(for: id)
        try savePositionBook(updated)
    }

    private func savePositionBook(_ updated: PositionBook) throws {
        let encoded = try JSONEncoder().encode(updated)
        defaults.set(encoded, forKey: "positionBook")
        positionBook = updated
    }

    func start() {
        scheduleRefresh()
        scheduleRotation()
        scheduleNotification()
        Task { await refresh() }
    }

    func refresh() async {
        if let refreshTask {
            await refreshTask.value
            return
        }
        let instruments = preferences.stockIDs.compactMap(Instrument.init)
        let client = self.client
        lastRefreshStarted = .now
        let task = Task {
            defer {
                saveQuotes()
                refreshTask = nil
            }
            async let gold = Self.attempt { try await client.gold() }
            async let stocks = Self.attempt { try await client.stocks(instruments) }
            var fresh: [String: Quote] = [:]

            switch await gold {
            case .success(let quote):
                if record(quote, for: Instrument.goldID) { fresh[Instrument.goldID] = quote }
            case .failure(let error): errors[Instrument.goldID] = error.localizedDescription
            }
            switch await stocks {
            case .success(let batch):
                for instrument in instruments where preferences.stockIDs.contains(instrument.id) {
                    if let quote = batch[instrument.id] {
                        if record(quote, for: instrument.id) { fresh[instrument.id] = quote }
                    } else {
                        errors[instrument.id] = QuoteError.missingStock.localizedDescription
                    }
                }
            case .failure(let error):
                for instrument in instruments where preferences.stockIDs.contains(instrument.id) {
                    errors[instrument.id] = error.localizedDescription
                }
            }
            await priceAlerts.evaluate(fresh) { allIDs.contains($0) }
        }
        refreshTask = task
        await task.value
    }

    func addStock(_ text: String) async -> String? {
        guard !addingStock else { return nil }
        guard let instrument = Instrument(text) else {
            return "代码格式不正确，可输入 600519、159934、00700 或 AAPL。"
        }
        guard !preferences.stockIDs.contains(instrument.id) else { return "已添加此代码。" }
        guard preferences.stockIDs.count < Self.stockLimit else { return "最多添加 \(Self.stockLimit) 只自选股。" }
        addingStock = true
        defer { addingStock = false }
        do {
            guard let quote = try await client.stocks([instrument])[instrument.id] else {
                throw QuoteError.missingStock
            }
            record(quote, for: instrument.id)
            preferences.stockIDs.append(instrument.id)
            saveQuotes()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func removeStock(_ id: String) {
        var edited = preferences
        edited.stockIDs.removeAll { $0 == id }
        edited.normalize()
        preferences = edited
        if positionID == id { positionID = Instrument.goldID }
        quotes.removeValue(forKey: id)
        errors.removeValue(forKey: id)
        trendCache.removeValue(forKey: id)
        saveQuotes()
    }

    func pin(_ id: String) {
        var edited = preferences
        edited.pinnedID = id
        edited.displayMode = .fixed
        preferences = edited
    }

    func setNotifications(_ enabled: Bool) async {
        if !enabled {
            preferences.notificationEnabled = false
            notificationMessage = nil
            return
        }
        guard !checkingNotifications else { return }
        checkingNotifications = true
        defer { checkingNotifications = false }
        do {
            preferences.notificationEnabled = try await notificationCenter.requestAuthorization(options: [.alert, .sound])
            notificationMessage = preferences.notificationEnabled ? nil : Self.permissionMessage
        } catch {
            notificationMessage = error.localizedDescription
        }
    }

    func sendNotification() async {
        guard preferences.notificationEnabled, !checkingNotifications else { return }
        checkingNotifications = true
        defer { checkingNotifications = false }
        let authorization = await notificationCenter.notificationSettings().authorizationStatus
        guard authorization == .authorized || authorization == .provisional else {
            preferences.notificationEnabled = false
            notificationMessage = Self.permissionMessage
            return
        }
        if refreshing || lastRefreshStarted.map({ Date.now.timeIntervalSince($0) > 20 }) != false {
            await refresh()
        }
        guard preferences.notificationEnabled else { return }

        let ids = preferences.notificationScope == .gold ? [Instrument.goldID] : allIDs
        let lines = ids.map { id in
            guard let quote = quotes[id] else { return "\(name(for: id)) · 暂无报价" }
            let time = quote.quotedAt == nil ? "报价时间未知" : quote.quoteTime
            let status = errors[id] == nil ? time : "缓存 · \(time)"
            return "\(quote.name) \(quote.formattedPrice(gold: id == Instrument.goldID)) · \(status)"
        }
        let content = UNMutableNotificationContent()
        content.title = preferences.notificationScope == .gold ? "浙商积存金" : "积存金与自选股"
        content.body = lines.joined(separator: "\n")
        content.sound = .default
        do {
            try await notificationCenter.add(UNNotificationRequest(
                identifier: "marketbar.latest", content: content, trigger: nil
            ))
            notificationMessage = "已发送 · \(Quote.displayTime(.now))"
        } catch {
            notificationMessage = error.localizedDescription
        }
    }

    private static let permissionMessage = "请在「系统设置 → 通知 → 行情栏」允许通知，再开启此选项。"

    @discardableResult
    private func record(_ quote: Quote, for id: String) -> Bool {
        if let existing = quotes[id],
           let previousTime = existing.quotedAt, let currentTime = quote.quotedAt,
           currentTime < previousTime {
            errors[id] = "接口返回了更早的行情，已保留较新的报价。"
            return false
        }
        quotes[id] = quote
        errors.removeValue(forKey: id)
        return true
    }

    private func saveQuotes() {
        defaults.set(try? JSONEncoder().encode(quotes), forKey: "quotes")
    }

    private func scheduleRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = timer(seconds: preferences.refreshMinutes * 60) { await $0.refresh() }
    }

    private func scheduleRotation() {
        rotationTimer?.invalidate()
        rotationTimer = nil
        guard preferences.displayMode == .rotation, rotationIDs.count > 1 else { return }
        rotationTimer = timer(seconds: preferences.rotationSeconds) {
            $0.rotationIndex = ($0.rotationIndex + 1) % $0.rotationIDs.count
        }
    }

    private func scheduleNotification() {
        notificationTimer?.invalidate()
        notificationTimer = nil
        guard preferences.notificationEnabled else { return }
        notificationTimer = timer(seconds: preferences.notificationMinutes * 60) { await $0.sendNotification() }
    }

    private func timer(seconds: Int, action: @escaping @MainActor (MarketStore) async -> Void) -> Timer {
        let timer = Timer(timeInterval: Double(seconds), repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                await action(self)
            }
        }
        timer.tolerance = min(5, Double(seconds) * 0.1)
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    private nonisolated static func attempt<Value: Sendable>(
        _ request: @Sendable () async throws -> Value
    ) async -> Result<Value, Error> {
        do { return .success(try await request()) }
        catch { return .failure(error) }
    }
}
