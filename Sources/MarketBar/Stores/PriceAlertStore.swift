import Foundation
import Observation
import UserNotifications

@MainActor
@Observable
final class PriceAlertStore {
    private let defaults: UserDefaults
    private let center = UNUserNotificationCenter.current()

    private(set) var rules: [PriceAlertRule]
    private(set) var authorization: UNAuthorizationStatus?
    private(set) var requestingPermission = false
    private(set) var message: String?

    init(defaults: UserDefaults) {
        self.defaults = defaults
        rules = defaults.data(forKey: "priceAlerts").flatMap {
            try? JSONDecoder().decode([PriceAlertRule].self, from: $0)
        } ?? []
    }

    var canNotify: Bool { authorization == .authorized || authorization == .provisional }

    func updateAuthorization() async {
        authorization = await center.notificationSettings().authorizationStatus
    }

    func requestPermission() async {
        guard !requestingPermission else { return }
        requestingPermission = true
        defer { requestingPermission = false }
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
            message = nil
        } catch {
            message = error.localizedDescription
        }
        await updateAuthorization()
    }

    func save(id: UUID?, criteria: PriceAlertRule.Criteria) {
        if let id {
            guard let index = rules.firstIndex(where: { $0.id == id }), rules[index].criteria != criteria else { return }
            rules[index] = PriceAlertRule(id: id, criteria: criteria, enabled: rules[index].enabled)
        } else {
            rules.append(PriceAlertRule(id: UUID(), criteria: criteria))
        }
        persist()
    }

    func setEnabled(_ enabled: Bool, id: UUID) {
        guard let index = rules.firstIndex(where: { $0.id == id }), rules[index].enabled != enabled else { return }
        rules[index].enabled = enabled
        rules[index].lastDirection = nil
        rules[index].lastReference = nil
        persist()
    }

    func remove(id: UUID) {
        rules.removeAll { $0.id == id }
        persist()
    }

    func evaluate(_ freshQuotes: [String: Quote], isTracked: (String) -> Bool) async {
        guard rules.contains(where: { $0.enabled && freshQuotes[$0.criteria.instrumentID] != nil }) else { return }
        await updateAuthorization()
        guard canNotify else { return }

        var changed = false
        for rule in rules where rule.enabled {
            let instrumentID = rule.criteria.instrumentID
            guard isTracked(instrumentID), let quote = freshQuotes[instrumentID],
                  let reading = rule.reading(for: quote), let index = currentIndex(for: rule) else { continue }
            if rule.shouldNotify(reading), let direction = reading.direction {
                do {
                    try await notify(rule, quote: quote, direction: direction, magnitude: reading.magnitude)
                    if let index = currentIndex(for: rule) {
                        rules[index].accept(reading, triggeredAt: .now)
                        changed = true
                    }
                    message = nil
                } catch {
                    message = error.localizedDescription
                }
            } else if rule.lastDirection != reading.direction || rule.lastReference != reading.reference {
                rules[index].accept(reading)
                changed = true
            }
        }
        if changed { persist() }
    }

    private func currentIndex(for rule: PriceAlertRule) -> Int? {
        rules.firstIndex { $0.id == rule.id && $0.criteria == rule.criteria && $0.enabled }
    }

    private func notify(_ rule: PriceAlertRule, quote: Quote, direction: PriceAlertRule.Direction,
                        magnitude: Decimal) async throws {
        let gold = rule.criteria.instrumentID == Instrument.goldID
        let reference = rule.criteria.referencePrice.map { "较参考价 \(PriceAlertRule.numberText($0))" } ?? "较昨收"
        let change = magnitude.formatted(.number.precision(.fractionLength(0...8)))
        let content = UNMutableNotificationContent()
        content.title = "\(quote.name) · 价格提醒"
        content.body = "\(reference)\(direction.label) \(change) \(rule.criteria.unit) · 现价 \(quote.formattedPrice(gold: gold))\n报价 \(quote.quoteTime)"
        content.sound = .default
        try await center.add(UNNotificationRequest(
            identifier: "marketbar.price.\(rule.id.uuidString)", content: content, trigger: nil
        ))
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(rules) { defaults.set(data, forKey: "priceAlerts") }
    }
}
