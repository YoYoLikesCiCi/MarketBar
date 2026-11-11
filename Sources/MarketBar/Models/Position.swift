import Foundation

struct Position: Codable, Equatable {
    let quantity: Decimal?
    let unitCost: Decimal?

    struct Valuation {
        let marketValue: Decimal
        let gain: Decimal?
        let gainPercent: Decimal?
    }

    enum InputError: LocalizedError {
        case quantity, unitCost

        var errorDescription: String? {
            let field = self == .quantity ? "持仓份额" : "成本价"
            return "\(field)请输入非负数字，最多 8 位小数。"
        }
    }

    private static let inputLocale = Locale(identifier: "en_US_POSIX")

    init(quantityText: String, unitCostText: String) throws {
        let quantity = try Self.parse(quantityText, error: .quantity)
        self.quantity = quantity == 0 ? nil : quantity
        self.unitCost = try Self.parse(unitCostText, error: .unitCost)
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
        guard let unitCost else {
            return Valuation(marketValue: marketValue, gain: nil, gainPercent: nil)
        }
        let cost = quantity * unitCost
        let gain = marketValue - cost
        let percent = cost > 0 ? gain / cost * 100 : nil
        return Valuation(marketValue: marketValue, gain: gain, gainPercent: percent)
    }

    private static func parse(_ input: String, error: InputError) throws -> Decimal? {
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
