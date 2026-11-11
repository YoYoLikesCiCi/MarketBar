import SwiftUI

struct SettingsOptionRow<Content: View>: View {
    let title: String
    var detail: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .medium))
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            content
        }
        .frame(minHeight: 32)
    }
}

struct SettingsSegments<Value: Hashable>: View {
    let title: String
    let values: [Value]
    @Binding var selection: Value
    let label: (Value) -> String

    var body: some View {
        HStack(spacing: 3) {
            ForEach(values, id: \.self) { item in
                let selected = selection == item
                Button {
                    selection = item
                } label: {
                    Text(label(item))
                        .font(.system(size: 12, weight: selected ? .semibold : .medium))
                        .foregroundStyle(selected ? Color.primary : .secondary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(.primary.opacity(selected ? 0.09 : 0),
                                    in: RoundedRectangle(cornerRadius: 7))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

struct SettingsSelect<Value: Hashable>: View {
    let title: String
    let values: [Value]
    @Binding var selection: Value
    let label: (Value) -> String

    var body: some View {
        Menu {
            ForEach(values, id: \.self) { option in
                Button {
                    selection = option
                } label: {
                    if option == selection { Label(label(option), systemImage: "checkmark") }
                    else { Text(label(option)) }
                }
            }
        } label: {
            HStack(spacing: 9) {
                Text(label(selection)).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 11)
            .frame(height: 32)
            .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(title)
        .accessibilityValue(label(selection))
    }
}

struct SettingsTextField: View {
    let title: String
    @Binding var text: String
    var prompt: String = ""
    var unit: String? = nil
    var numeric = false

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 7) {
            TextField(title, text: $text, prompt: Text(prompt))
                .labelsHidden()
                .textFieldStyle(.plain)
                .multilineTextAlignment(numeric ? .trailing : .leading)
                .monospacedDigit()
                .focused($focused)
            if let unit {
                Text(unit).font(.caption).foregroundStyle(.secondary)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(focused ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.10))
                .allowsHitTesting(false)
        }
    }
}
