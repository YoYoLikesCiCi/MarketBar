import AppKit
import SwiftUI

struct MenuBarPriceLabel: View {
    let quote: MenuBarQuote
    var isPreview = false

    var body: some View {
        if let tint {
            if isPreview {
                Text("\(Text(verbatim: quote.prefix))\(Text(verbatim: quote.price).foregroundColor(tint))\(Text(verbatim: quote.suffix))")
            } else {
                Image(nsImage: makeImage(priceColor: NSColor(tint)))
            }
        } else {
            Text(verbatim: quote.title).monospacedDigit()
        }
    }

    private var tint: Color? {
        guard let change = quote.changePercent, change.isFinite, change != 0 else { return nil }
        return MarketAppearance.movementColor(id: quote.id, sign: change > 0 ? 1 : -1)
    }

    // MenuBarExtra discards text color. An original image preserves it.
    private func makeImage(priceColor: NSColor) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular)
        let text = NSMutableAttributedString(string: quote.title, attributes: [
            .font: font,
            .foregroundColor: NSColor.labelColor
        ])
        let priceRange = NSRange(location: quote.prefix.utf16.count, length: quote.price.utf16.count)
        text.addAttribute(.foregroundColor, value: priceColor, range: priceRange)
        let size = text.size()
        let image = NSImage(size: NSSize(width: ceil(size.width), height: ceil(size.height)), flipped: true) { _ in
            text.draw(at: .zero)
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = quote.title
        return image
    }
}
