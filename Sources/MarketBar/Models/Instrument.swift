import Foundation

struct Instrument: Hashable, Sendable {
    enum Market: String, Sendable {
        case sh, sz, bj, hk, us
    }

    static let goldID = "czbank-gold"
    let market: Market
    let code: String

    var id: String { market.rawValue + code }
    var timeZone: TimeZone { TimeZone(identifier: market == .us ? "America/New_York" : "Asia/Shanghai")! }

    var currency: String {
        if market == .us || (market == .sh && code.hasPrefix("900")) { return "USD" }
        if market == .hk || (market == .sz && code.hasPrefix("200")) { return "HKD" }
        return "CNY"
    }

    init?(_ input: String) {
        let raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
        var code = raw.uppercased()
        let market: Market
        let suffix = code.dropFirst(2).trimmingCharacters(in: .whitespaces)
        if let explicitMarket = Market(rawValue: String(code.prefix(2)).lowercased()),
           explicitMarket != .us, suffix.first?.isNumber == true {
            market = explicitMarket
            code = suffix
        } else if code.hasPrefix("US:") || code.hasPrefix("US ") ||
                    (raw.hasPrefix("us") && raw.dropFirst(2).first?.isUppercase == true) {
            market = .us
            code = code.hasPrefix("US:") ? String(code.dropFirst(3)) : suffix
        } else if code.hasSuffix(".HK") {
            market = .hk
            code = String(code.dropLast(3))
        } else if code.range(of: #"^[0-9]{6}$"#, options: .regularExpression) != nil {
            switch code.first {
            case "5", "6": market = .sh
            case "9" where !code.hasPrefix("92"): market = .sh
            case "0", "1", "2", "3": market = .sz
            case "4", "8", "9": market = .bj
            default: return nil
            }
        } else if code.range(of: #"^[0-9]{4,5}$"#, options: .regularExpression) != nil {
            market = .hk
        } else {
            market = .us
        }

        switch market {
        case .sh, .sz, .bj:
            guard code.range(of: #"^[0-9]{6}$"#, options: .regularExpression) != nil else { return nil }
        case .hk:
            guard code.range(of: #"^[0-9]{1,5}$"#, options: .regularExpression) != nil else { return nil }
            code = String(repeating: "0", count: 5 - code.count) + code
        case .us:
            guard code.range(of: #"^[A-Z]{1,8}([.-][A-Z]{1,3})?$"#, options: .regularExpression) != nil else { return nil }
        }

        self.market = market
        self.code = code
    }
}

struct Quote: Codable, Sendable {
    let name: String
    let price: Double
    let changePercent: Double?
    let quotedAt: Date?
    let fetchedAt: Date
    let currency: String

    func formattedPrice(gold: Bool) -> String {
        let decimals = gold ? 2 : (price < 1 ? 4 : 3)
        let amount = price.formatted(.number.precision(.fractionLength(2...decimals)).grouping(.never))
        if gold { return "¥\(amount)/克" }
        let symbol = ["CNY": "¥", "HKD": "HK$", "USD": "US$"][currency] ?? "\(currency) "
        return symbol + amount
    }

    var formattedChange: String? {
        changePercent.map {
            ($0 > 0 ? "+" : "") + $0.formatted(.number.precision(.fractionLength(2))) + "%"
        }
    }

    var quoteTime: String {
        guard let quotedAt else { return "未知" }
        return Self.displayTime(quotedAt)
    }

    static func displayTime(_ date: Date) -> String {
        let style = Date.FormatStyle(
            locale: Locale(identifier: "zh_CN"),
            timeZone: TimeZone(identifier: "Asia/Shanghai")!
        ).month(.twoDigits).day(.twoDigits).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
        return date.formatted(style)
    }
}
