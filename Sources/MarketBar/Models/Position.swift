import Foundation

struct Position: Codable, Equatable {
    let quantity: Decimal?
    private let enteredUnitCost: Decimal?
    private let recordedCostBasis: Decimal?

    private enum CodingKeys: String, CodingKey {
        case quantity, enteredUnitCost = "unitCost", recordedCostBasis
    }

    struct Valuation {
        let marketValue: Decimal
        let gain: Decimal?
        let gainPercent: Decimal?
    }

    enum InputError: LocalizedError {
        case quantity, unitCost, tradeQuantity, tradePrice, tradeFee

        var errorDescription: String? {
            switch self {
            case .quantity: "持仓份额请输入非负数字，最多 8 位小数。"
            case .unitCost: "成本价请输入非负数字，最多 8 位小数。"
            case .tradeQuantity: "成交份额须大于 0，最多 8 位小数。"
            case .tradePrice: "成交单价须大于 0，最多 8 位小数。"
            case .tradeFee: "手续费请输入非负数字，最多 8 位小数。"
            }
        }
    }

    private static let inputLocale = Locale(identifier: "en_US_POSIX")

    init(quantityText: String, unitCostText: String) throws {
        let quantity = try Self.parse(quantityText, error: .quantity)
        self.quantity = quantity == 0 ? nil : quantity
        enteredUnitCost = try Self.parse(unitCostText, error: .unitCost)
        recordedCostBasis = nil
    }

    init(quantity: Decimal, costBasis: Decimal?) {
        self.quantity = quantity
        enteredUnitCost = nil
        recordedCostBasis = costBasis
    }

    var unitCost: Decimal? {
        if let recordedCostBasis, let quantity, quantity > 0 { return recordedCostBasis / quantity }
        return enteredUnitCost
    }

    var costBasis: Decimal? {
        if let recordedCostBasis { return recordedCostBasis }
        guard let quantity, let enteredUnitCost else { return nil }
        return quantity * enteredUnitCost
    }

    var isEmpty: Bool { quantity == nil && unitCost == nil }

    var quantityText: String { quantity.map(Self.editableNumber) ?? "" }
    var unitCostText: String { unitCost.map(Self.editableNumber) ?? "" }

    func valuation(at price: Double?) -> Valuation? {
        guard let quantity, quantity > 0, let price, price.isFinite, price > 0,
              let quote = Decimal(string: String(price), locale: Self.inputLocale), quote > 0 else {
            return nil
        }
        let marketValue = quantity * quote
        guard let cost = costBasis else {
            return Valuation(marketValue: marketValue, gain: nil, gainPercent: nil)
        }
        let gain = marketValue - cost
        let percent = cost > 0 ? gain / cost * 100 : nil
        return Valuation(marketValue: marketValue, gain: gain, gainPercent: percent)
    }

    static func parse(_ input: String, error: InputError) throws -> Decimal? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: .widthInsensitive, locale: inputLocale)
        guard !text.isEmpty else { return nil }
        guard text.range(of: #"^(?:[0-9]{1,15}(?:\.[0-9]{0,8})?|\.[0-9]{1,8})$"#, options: .regularExpression) != nil,
              let number = Decimal(string: text, locale: inputLocale) else {
            throw error
        }
        return number
    }

    private static func editableNumber(_ value: Decimal) -> String {
        value.formatted(.number.locale(inputLocale).grouping(.never).precision(.fractionLength(0...8)))
    }
}
