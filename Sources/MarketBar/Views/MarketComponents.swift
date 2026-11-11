import SwiftUI

enum MarketAppearance {
    static let gold = Color(red: 0.83, green: 0.61, blue: 0.21)

    static func movementColor(id: String, sign: Int) -> Color {
        guard sign != 0 else { return .secondary }
        let risesInGreen = Instrument(id)?.market == .us
        return (sign > 0) == risesInGreen ? .green : .red
    }
}

struct MarketGlyph: View {
    let symbol: String
    var tint: Color = .accentColor
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: size, height: size)
            .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: size * 0.29))
            .accessibilityHidden(true)
    }
}

struct MarketIconButton: View {
    let label: String
    let symbol: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 30, height: 30)
                .background(.primary.opacity(hovering ? 0.10 : 0.04), in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(label)
        .help(label)
    }
}

struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(title).font(.system(size: 13, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            content
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.primary.opacity(0.07))
                .allowsHitTesting(false)
        }
    }
}
