import SwiftUI

/// A capsule tag. Filled accent = confirmed; dashed outline = an AI suggestion awaiting approval.
struct TagChip: View {
    enum Style {
        case confirmed
        case suggested
        case neutral
        case common
        case muted
    }

    let name: String
    var style: Style = .neutral
    var count: String? = nil
    var symbol: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.caption.weight(.semibold))
                    .imageScale(.small)
            }
            Text(name)
                .lineLimit(1)
            if let count {
                Text(count)
                    .monospacedDigit()
                    .opacity(0.7)
            }
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .foregroundStyle(foreground)
        .background(background)
        .contentShape(Capsule())
    }

    private var foreground: Color {
        switch style {
        case .confirmed, .common: Theme.onAccent
        case .suggested: .primary
        case .neutral: .primary
        case .muted: .secondary
        }
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .confirmed:
            Capsule().fill(Theme.accent)
        case .common:
            Capsule().fill(Theme.accent)
                .shadow(color: Theme.accent.opacity(0.45), radius: 10)
        case .suggested:
            Capsule().strokeBorder(Theme.accent.opacity(0.8), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
        case .neutral:
            Capsule().fill(Theme.raised)
        case .muted:
            Capsule().fill(Theme.surface)
        }
    }
}

/// Any feeling, reference or ingredient, anywhere: tap to open its Learn card.
struct LearnChip: View {
    let name: String
    /// Where the chip sits ("distill", "pantry"…); keeps zoom source ids unique per screen.
    let context: String
    var style: TagChip.Style = .neutral
    var count: String? = nil
    var symbol: String? = nil

    @Environment(\.learnNamespace) private var namespace

    var body: some View {
        let route = LearnRoute(name: name, context: context)
        NavigationLink(value: route) {
            TagChip(name: name, style: style, count: count, symbol: symbol)
                .zoomSource(id: route.sourceID, in: namespace)
        }
        .buttonStyle(PressableStyle())
        .accessibilityHint("Opens a Learn card")
    }
}

/// A wrapping cluster of Learn chips.
struct LearnChipCloud: View {
    let names: [String]
    let context: String
    var style: TagChip.Style = .neutral
    var counts: [String: String] = [:]

    var body: some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(names, id: \.self) { name in
                LearnChip(name: name, context: context, style: style, count: counts[name])
            }
        }
    }
}
