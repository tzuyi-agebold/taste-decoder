import SwiftUI

/// Marks where an imported collection came from.
/// Replace the drawn mark with Pinterest's official badge (brand resources) before shipping publicly.
struct SourceBadge: View {
    let source: CollectionSource
    /// Show "Pinterest" next to the mark.
    var showsLabel = false
    var size: CGFloat = 20

    var body: some View {
        HStack(spacing: 5) {
            mark
            if showsLabel {
                Text(source.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
            }
        }
        .padding(.leading, showsLabel ? 3 : 0)
        .padding(.trailing, showsLabel ? 8 : 0)
        .padding(.vertical, showsLabel ? 3 : 0)
        .background {
            if showsLabel { Capsule().fill(.ultraThinMaterial) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("From \(source.label)")
    }

    @ViewBuilder
    private var mark: some View {
        switch source {
        case .pinterest:
            ZStack {
                Circle().fill(Self.pinterestRed)
                Text("P")
                    .font(.system(size: size * 0.62, weight: .heavy, design: .serif))
                    .foregroundStyle(.white)
                    .offset(y: size * 0.02)
            }
            .frame(width: size, height: size)
        }
    }

    static let pinterestRed = Color(red: 230 / 255, green: 0, blue: 35 / 255)
}

/// An imported collection's cover images, laid out like `Mosaic`.
struct CoverMosaic: View {
    let names: [String]

    var body: some View {
        GeometryReader { proxy in
            let spacing = Theme.tileSpacing
            let visible = Array(names.prefix(3))
            HStack(spacing: spacing) {
                if let first = visible.first {
                    StoredImage(fileName: first, maxPixel: 700)
                        .frame(width: visible.count > 1 ? proxy.size.width * 0.62 : proxy.size.width, height: proxy.size.height)
                        .clipped()
                }
                if visible.count > 1 {
                    VStack(spacing: spacing) {
                        ForEach(visible.dropFirst(), id: \.self) { name in
                            StoredImage(fileName: name, maxPixel: 400)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .clipped()
                        }
                    }
                }
            }
        }
        .background(Theme.surface)
    }
}

/// The picture for a collection: its saves, else its imported covers, else its symbol.
struct CollectionVisual: View {
    let collection: TasteCollection
    let items: [SaveItem]

    var body: some View {
        if !items.isEmpty {
            Mosaic(items: items)
        } else if !collection.coverImageNames.isEmpty {
            CoverMosaic(names: collection.coverImageNames)
        } else {
            ZStack {
                Theme.surface
                Image(systemName: collection.symbol)
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
