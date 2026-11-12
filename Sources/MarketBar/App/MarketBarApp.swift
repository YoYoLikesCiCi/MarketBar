import AppKit
import SwiftUI
import UserNotifications

@main
struct MarketBarApp: App {
    @NSApplicationDelegateAdaptor(MarketBarDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            QuotesPanel(store: delegate.store)
        } label: {
            let quote = delegate.store.menuBarQuote
            MenuBarPriceLabel(quote: quote)
                .accessibilityLabel("行情栏 \(quote.title)")
        }
        .menuBarExtraStyle(.window)

        Window("行情栏设置", id: "preferences") {
            PreferencesView(store: delegate.store)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 748, height: 550)
        .defaultPosition(.center)
    }
}

@MainActor
final class MarketBarDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let store = MarketStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        UNUserNotificationCenter.current().delegate = self
        store.start()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
