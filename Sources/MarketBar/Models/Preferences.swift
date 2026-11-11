import Foundation

struct Preferences: Codable, Equatable {
    enum DisplayMode: String, CaseIterable, Codable, Identifiable {
        case fixed, rotation
        var id: Self { self }
        var label: String { self == .fixed ? "固定一项" : "轮播" }
    }

    enum LabelStyle: String, CaseIterable, Codable, Identifiable {
        case name, code, price
        var id: Self { self }
        var label: String {
            switch self {
            case .name: "名称和价格"
            case .code: "代码和价格"
            case .price: "仅价格"
            }
        }
    }

    enum NotificationScope: String, CaseIterable, Codable, Identifiable {
        case gold, watchlist
        var id: Self { self }
        var label: String { self == .gold ? "仅浙商积存金" : "积存金和自选股票" }
    }

    var stockIDs: [String] = []
    var refreshMinutes = 5
    var notificationEnabled = false
    var notificationMinutes = 30
    var notificationScope = NotificationScope.gold
    var displayMode = DisplayMode.fixed
    var pinnedID = Instrument.goldID
    var excludedFromRotation: Set<String> = []
    var rotationSeconds = 5
    var labelStyle = LabelStyle.name
    var showChange = false

    static let refreshRange = 1...120
    static let notificationRange = 1...1440
    static let rotationRange = 2...60

    mutating func normalize() {
        var seen = Set<String>()
        stockIDs = stockIDs.compactMap { Instrument($0)?.id }.filter { seen.insert($0).inserted }
        refreshMinutes = min(max(refreshMinutes, Self.refreshRange.lowerBound), Self.refreshRange.upperBound)
        notificationMinutes = min(max(notificationMinutes, Self.notificationRange.lowerBound), Self.notificationRange.upperBound)
        rotationSeconds = min(max(rotationSeconds, Self.rotationRange.lowerBound), Self.rotationRange.upperBound)
        let ids = Set(stockIDs + [Instrument.goldID])
        if !ids.contains(pinnedID) { pinnedID = Instrument.goldID }
        excludedFromRotation.formIntersection(ids)
    }
}
