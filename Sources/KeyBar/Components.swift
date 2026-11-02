import SwiftUI
import KeyBarCore

enum Palette {
    static let ink = Color(red: 0.16, green: 0.18, blue: 0.17)
    static let secondary = Color(red: 0.43, green: 0.45, blue: 0.43)
    static let paper = Color(red: 0.97, green: 0.97, blue: 0.95)
    static let sidebar = Color(red: 0.94, green: 0.94, blue: 0.91)
    static let accent = Color(red: 0.78, green: 0.31, blue: 0.20)
    static let line = Color.black.opacity(0.08)
}

extension Provider {
    var symbol: String {
        switch self {
        case .custom: "key.horizontal"
        case .gemini: "sparkles"
        case .openrouter: "arrow.triangle.branch"
        case .anthropic: "asterisk"
        case .openai: "circle.hexagongrid"
        }
    }
    var tint: Color {
        switch self {
        case .custom: Palette.secondary
        case .gemini: Color(red: 0.32, green: 0.44, blue: 0.72)
        case .openrouter: Palette.ink
        case .anthropic: Palette.accent
        case .openai: Color(red: 0.25, green: 0.49, blue: 0.39)
        }
    }
}

struct ProviderIcon: View {
    let provider: Provider
    var size: CGFloat = 38
    var body: some View {
        Image(systemName: provider.symbol)
            .font(.system(size: size * 0.44, weight: .medium))
            .foregroundStyle(provider.tint)
            .frame(width: size, height: size)
            .background(provider.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: size * 0.27))
            .accessibilityHidden(true)
    }
}

struct StatusBadge: View {
    let status: KeyStatus
    var checking = false
    private var color: Color {
        switch status {
        case .valid: Color(red: 0.19, green: 0.48, blue: 0.32)
        case .invalid: .red
        case .restricted, .rateLimited: .orange
        case .unchecked, .unavailable: Palette.secondary
        }
    }
    var body: some View {
        HStack(spacing: 5) {
            if checking { ProgressView().controlSize(.mini) }
            else { Circle().fill(color).frame(width: 6, height: 6) }
            Text(checking ? "Checking…" : status.label)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(color)
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(color.opacity(0.07), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 14).padding(.vertical, 10)
            .foregroundStyle(.white)
            .background(Palette.ink.opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.3), in: RoundedRectangle(cornerRadius: 9))
    }
}

struct SectionCaption: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(1.4).foregroundStyle(Palette.secondary)
    }
}
