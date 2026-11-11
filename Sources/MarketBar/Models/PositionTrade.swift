import Foundation

struct PositionTrade: Codable, Identifiable {
    enum Side: String, Codable, Identifiable {
        case buy, sell

        var id: Self { self }
        var label: String { self == .buy ? "加仓" : "减持" }
    }

    enum TradeError: LocalizedError {
        case exceedsHolding, notTracked, positionChanged, cannotUndo

        var errorDescription: String? {
            switch self {
            case .exceedsHolding: "减持份额不能超过当前持仓。"
            case .notTracked: "该品种已移出自选。"
            case .positionChanged: "持仓已更新，请重新确认这笔操作。"
            case .cannotUndo: "当前持仓已调整，无法撤销这笔操作。"
            }
        }
    }

    let id: UUID
    let recordedAt: Date
    let side: Side
    let quantity: Decimal
    let unitPrice: Decimal
    let fee: Decimal
    let previous: Position?
    let remaining: Position?
    let realizedGain: Decimal?

    init(side: Side, quantityText: String, priceText: String, feeText: String,
         position: Position?) throws {
        guard let quantity = try Position.parse(quantityText, error: .tradeQuantity), quantity > 0 else {
            throw Position.InputError.tradeQuantity
        }
        guard let unitPrice = try Position.parse(priceText, error: .tradePrice), unitPrice > 0 else {
            throw Position.InputError.tradePrice
        }
        let fee = try Position.parse(feeText, error: .tradeFee) ?? 0
        let held = position?.quantity ?? 0
        let amount = quantity * unitPrice

        switch side {
        case .buy:
            let previousBasis: Decimal? = held > 0 ? position?.costBasis : 0
            remaining = Position(quantity: held + quantity, costBasis: previousBasis.map { $0 + amount + fee })
            realizedGain = nil
        case .sell:
            guard quantity <= held else { throw TradeError.exceedsHolding }
            let soldBasis = position?.costBasis.map { quantity == held ? $0 : $0 * quantity / held }
            let remainingBasis = position?.costBasis.flatMap { basis in soldBasis.map { basis - $0 } }
            remaining = quantity == held ? nil : Position(quantity: held - quantity, costBasis: remainingBasis)
            realizedGain = soldBasis.map { amount - fee - $0 }
        }

        id = UUID()
        recordedAt = .now
        self.side = side
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.fee = fee
        previous = position
    }
}

struct PositionBook: Codable {
    var positions: [String: Position] = [:]
    private(set) var trades: [String: [PositionTrade]] = [:]

    static func load(book: Data?, legacyPositions: Data?) -> Self {
        let decoder = JSONDecoder()
        if let book, let saved = try? decoder.decode(Self.self, from: book) { return saved }
        let previous = legacyPositions.flatMap { try? decoder.decode([String: Position].self, from: $0) }
        return Self(positions: previous ?? [:])
    }

    mutating func record(_ trade: PositionTrade, for id: String) throws {
        guard positions[id] == trade.previous, trades[id]?.last?.id != trade.id else {
            throw PositionTrade.TradeError.positionChanged
        }
        positions[id] = trade.remaining
        trades[id, default: []].append(trade)
    }

    func canUndo(for id: String) -> Bool {
        guard let last = trades[id]?.last else { return false }
        return positions[id] == last.remaining
    }

    mutating func undoLastTrade(for id: String) throws {
        guard canUndo(for: id), let last = trades[id]?.removeLast() else {
            throw PositionTrade.TradeError.cannotUndo
        }
        positions[id] = last.previous
    }
}
