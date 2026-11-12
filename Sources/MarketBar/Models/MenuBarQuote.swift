struct MenuBarQuote {
    let id: String
    let prefix: String
    let price: String
    let suffix: String
    let changePercent: Double?

    var title: String { prefix + price + suffix }
}
