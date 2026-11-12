import AppKit
import SwiftUI

enum PriceNotificationImage {
    @MainActor
    static func png(price: String, tint: Color) -> Data? {
        let text = NSAttributedString(string: price, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 68, weight: .semibold),
            .foregroundColor: NSColor(tint)
        ])
        let textSize = text.size()
        let width = max(560, Int(ceil(textSize.width)) + 88)
        let height = Int(ceil(textSize.height)) + 56
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                            isPlanar: false, colorSpaceName: .deviceRGB,
                                            bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()
        text.draw(at: NSPoint(x: (CGFloat(width) - textSize.width) / 2,
                              y: (CGFloat(height) - textSize.height) / 2))
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])
    }
}
