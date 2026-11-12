import Foundation

extension QuoteClient {
    func trend(for id: String, period: QuoteTrendPeriod) async throws -> [QuoteTrendPoint] {
        if id == Instrument.goldID {
            let endpoint = period == .today ? "cfGetPriceTrendChart" : "cfGetQuotesPriceKLine"
            let parameters = period == .today
                ? ["productSku": Self.goldSKU, "appChannel": "11", "priceType": "buy", "beginTime": ""]
                : ["productSku": Self.goldSKU, "periodType": "m1"]
            let json = try JSONEncoder().encode(parameters)
            var url = URLComponents(string: "https://api.jdjygold.com/gw2/generic/hj/h5/m/\(endpoint)")!
            url.queryItems = [.init(name: "reqData", value: String(decoding: json, as: UTF8.self))]
            let response = try await data(from: url.url!, referer: "https://m.jdjygold.com/")
            return try Self.parseGoldTrend(response, period: period)
        }

        guard let instrument = Instrument(id) else { throw QuoteError.invalidResponse }
        return try await stockTrend(instrument, period: period)
    }

    private func stockTrend(_ instrument: Instrument, period: QuoteTrendPeriod) async throws -> [QuoteTrendPoint] {
        func load(code: String) async throws -> [String: Any] {
            let path = period == .today ? "minute/query" : "kline/kline"
            let query = period == .today ? URLQueryItem(name: "code", value: code)
                                        : URLQueryItem(name: "param", value: "\(code),day,,,32")
            var url = URLComponents(string: "https://web.ifzq.gtimg.cn/appstock/app/\(path)")!
            url.queryItems = [query]
            let response = try await data(from: url.url!, referer: "https://gu.qq.com/")
            guard let json = try JSONSerialization.jsonObject(with: response) as? [String: Any],
                  json["code"] as? Int == 0,
                  let data = json["data"] as? [String: Any], let series = data[code] as? [String: Any] else {
                throw QuoteError.invalidResponse
            }
            return series
        }

        let initial = try await load(code: instrument.id)
        var series = initial
        if instrument.market == .us, period == .month,
           let quote = Self.stockTrendQuote(initial, code: instrument.id),
           quote[2].hasPrefix(instrument.code + "."),
           quote[2].range(of: #"^[A-Z0-9.-]+$"#, options: .regularExpression) != nil {
            series = try await load(code: "us" + quote[2])
        }
        return try Self.parseStockTrend(series, instrument: instrument, period: period)
    }

    static func parseGoldTrend(_ data: Data, period: QuoteTrendPeriod) throws -> [QuoteTrendPoint] {
        let intraday = period == .today
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["resultCode"] as? Int == 0,
              let result = json["resultData"] as? [String: Any], result["code"] as? String == "00000000",
              let data = result["data"] as? [String: Any],
              let rows = data[intraday ? "dataList" : "line"] as? [[String: Any]] else {
            throw QuoteError.invalidResponse
        }
        let formatter = trendFormatter(intraday ? "yyyy-MM-dd HH:mm:ss" : "yyyyMMdd",
                                       timeZone: QuoteTrendPoint.calendar(for: Instrument.goldID).timeZone)
        return QuoteTrendPoint.ordered(rows.compactMap { row in
            guard let time = row[intraday ? "goldPriceTime" : "date"] as? String,
                  let date = formatter.date(from: time),
                  let price = trendPrice(row[intraday ? "goldPrice" : "price"]) else { return nil }
            return QuoteTrendPoint(date: date, price: price)
        })
    }

    static func parseStockTrend(_ series: [String: Any], instrument: Instrument,
                                period: QuoteTrendPeriod) throws -> [QuoteTrendPoint] {
        let points: [QuoteTrendPoint]
        if period == .today {
            guard let result = series["data"] as? [String: Any], let rows = result["data"] as? [String] else {
                throw QuoteError.invalidResponse
            }
            let stamp = stockTrendQuote(series, code: instrument.id)?[30] ?? ""
            let reportedDay = result["date"] as? String ?? ""
            let day = reportedDay.isEmpty ? String(stamp.prefix(10).filter(\.isNumber).prefix(8)) : reportedDay
            let formatter = trendFormatter("yyyyMMddHHmm", timeZone: instrument.timeZone)
            points = rows.compactMap { row in
                let fields = row.split(separator: " ")
                guard fields.count >= 2, fields[0].count == 4, day.count == 8,
                      let date = formatter.date(from: day + fields[0]),
                      let price = trendPrice(String(fields[1])) else { return nil }
                return QuoteTrendPoint(date: date, price: price)
            }
        } else {
            guard let rows = series["day"] as? [[Any]] else { throw QuoteError.invalidResponse }
            let formatter = trendFormatter("yyyy-MM-dd", timeZone: instrument.timeZone)
            points = rows.compactMap { row in
                guard row.count >= 3, let time = row[0] as? String, let date = formatter.date(from: time),
                      let price = trendPrice(row[2]) else { return nil }
                return QuoteTrendPoint(date: date, price: price)
            }
        }
        return QuoteTrendPoint.ordered(points)
    }

    private static func stockTrendQuote(_ series: [String: Any], code: String) -> [String]? {
        guard let quotes = series["qt"] as? [String: Any],
              let fields = quotes[code] as? [String], fields.count > 30 else { return nil }
        return fields
    }

    private static func trendFormatter(_ format: String, timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter
    }

    private static func trendPrice(_ value: Any?) -> Double? {
        let price = (value as? String).flatMap(Double.init) ?? (value as? NSNumber)?.doubleValue
        guard let price, price.isFinite, price > 0 else { return nil }
        return price
    }
}
