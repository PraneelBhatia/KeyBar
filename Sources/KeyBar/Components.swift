import SwiftUI
import KeyBarCore

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
}

struct ProviderIcon: View {
    let provider: Provider
    var size: CGFloat = 32
    var body: some View {
        Image(systemName: provider.symbol)
            .font(.system(size: size * 0.45, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            .accessibilityHidden(true)
    }
}

struct StatusBadge: View {
    let status: KeyStatus
    var checking = false
    private var color: Color {
        switch status {
        case .valid: .green
        case .invalid: .red
        case .restricted, .rateLimited: .orange
        case .unchecked, .unavailable: .secondary
        }
    }
    var body: some View {
        HStack(spacing: 5) {
            if checking { ProgressView().controlSize(.mini) }
            else { Circle().fill(color).frame(width: 6, height: 6) }
            Text(checking ? "Checking…" : status.label)
        }
        .font(.callout)
        .foregroundStyle(color)
        .accessibilityElement(children: .combine)
        .help(checking ? "Checking access with the provider." : status.explanation)
        .accessibilityHint(status.explanation)
    }
}

struct NativeActionGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: 12) { content() }
        } else { content() }
    }
}

extension View {
    @ViewBuilder func keybarPrimaryButton() -> some View {
        if #available(macOS 26, *) { buttonStyle(.glassProminent) }
        else { buttonStyle(.borderedProminent) }
    }

    @ViewBuilder func keybarGlassButton() -> some View {
        if #available(macOS 26, *) { buttonStyle(.glass) }
        else { buttonStyle(.bordered) }
    }

    @ViewBuilder func keybarDragSurface() -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular.interactive(), in: .capsule)
        } else {
            background(.regularMaterial, in: Capsule())
        }
    }
}
