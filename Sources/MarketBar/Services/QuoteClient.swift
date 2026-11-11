import CoreFoundation
import Foundation

enum QuoteError: LocalizedError {
    case http(Int)
    case invalidResponse
    case missingStock

    var errorDescription: String? {
        switch self {
        case .http(let status): "行情接口返回 HTTP \(status)。"
        case .invalidResponse: "行情接口返回的数据无法识别。"
        case .missingStock: "腾讯财经未返回此代码的有效报价，请检查代码和市场。"
        }
    }
}

struct QuoteClient: Sendable {
    private static let goldSKU = "1961543816"
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 15
        config.httpShouldSetCookies = false
        session = URLSession(configuration: config)
    }

    func gold() async throws -> Quote {
        let url = URL(string: "https://api.jdjygold.com/gw2/generic/jrm/h5/m/stdLatestPrice?productSku=\(Self.goldSKU)")!
        return try Self.parseGold(await data(from: url, referer: "https://m.jdjygold.com/"))
    }

    func stocks(_ instruments: [Instrument]) async throws -> [String: Quote] {
        guard !instruments.isEmpty else { return [:] }
        let codes = instruments.map(\.id).joined(separator: ",")
        let url = URL(string: "https://qt.gtimg.cn/q=\(codes)")!
        return try Self.parseStocks(await data(from: url, referer: "https://gu.qq.com/"), instruments: instruments)
    }

    private func data(from url: URL, referer: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(referer, forHTTPHeaderField: "Referer")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw QuoteError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else { throw QuoteError.http(response.statusCode) }
        return data
    }

    static func parseGold(_ data: Data, received: Date = .now) throws -> Quote {
        guard let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              response["success"] as? Bool == true,
              let result = response["resultData"] as? [String: Any],
              result["status"] as? String == "SUCCESS",
              let fields = result["datas"] as? [String: Any],
              fields["productSku"] as? String == goldSKU,
              let price = number(fields["price"]), price > 0 else {
            throw QuoteError.invalidResponse
        }
        let time = number(fields["time"]).flatMap { value -> Date? in
            guard value > 0 else { return nil }
            return Date(timeIntervalSince1970: value > 10_000_000_000 ? value / 1000 : value)
        }
        return Quote(name: "浙商积存金", price: price, changePercent: number(fields["upAndDownRate"]),
                     quotedAt: time, fetchedAt: received, currency: "CNY",
                     previousClose: positiveDecimal(fields["yesterdayPrice"]))
    }

    static func parseStocks(_ data: Data, instruments: [Instrument], received: Date = .now) throws -> [String: Quote] {
        let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        ))
        guard let body = String(data: data, encoding: .utf8) ?? String(data: data, encoding: gb18030) else {
            throw QuoteError.invalidResponse
        }
        let records = body.split(separator: ";").compactMap { record -> (String, Substring)? in
            guard let equals = record.firstIndex(of: "=") else { return nil }
            let key = record[..<equals].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = record[record.index(after: equals)...].trimmingCharacters(in: .whitespacesAndNewlines)
            guard (key.hasPrefix("v_") || key.hasPrefix("pv_")),
                  value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 else { return nil }
            return (key.lowercased(), value.dropFirst().dropLast())
        }
        guard !records.isEmpty else { throw QuoteError.invalidResponse }

        let quotesByKey = Dictionary(records, uniquingKeysWith: { _, last in last })
        var quotes: [String: Quote] = [:]
        for instrument in instruments {
            guard let raw = quotesByKey["v_" + instrument.id.lowercased()] else { continue }
            let fields = raw.split(separator: "~", omittingEmptySubsequences: false)
            guard fields.count > 32, let price = number(String(fields[3])), price > 0 else { continue }
            let name = fields[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = instrument.timeZone
            let timestamp = String(fields[30])
            if timestamp.contains("/") {
                formatter.dateFormat = "yyyy/MM/dd HH:mm:ss"
            } else if timestamp.contains("-") {
                formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            } else {
                formatter.dateFormat = "yyyyMMddHHmmss"
            }
            quotes[instrument.id] = Quote(
                name: name, price: price, changePercent: number(String(fields[32])),
                quotedAt: formatter.date(from: timestamp), fetchedAt: received, currency: instrument.currency,
                previousClose: positiveDecimal(String(fields[4]))
            )
        }
        return quotes
    }

    private static func positiveDecimal(_ value: Any?) -> Decimal? {
        let text = (value as? String) ?? (value as? NSNumber)?.stringValue
        guard let text,
              let number = Decimal(string: text.trimmingCharacters(in: .whitespacesAndNewlines),
                                   locale: Locale(identifier: "en_US_POSIX")),
              number > 0 else { return nil }
        return number
    }

    private static func number(_ value: Any?) -> Double? {
        let number: Double?
        if let text = value as? String {
            number = Double(text.trimmingCharacters(in: CharacterSet(charactersIn: "% ")))
        } else {
            number = value as? Double
        }
        guard let number, number.isFinite else { return nil }
        return number
    }
}
