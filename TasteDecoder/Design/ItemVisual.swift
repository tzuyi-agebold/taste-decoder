import SwiftUI

/// Renders a save: its photo, its procedural demo art, or a typographic card for notes and links.
struct ItemVisual: View {
    let item: SaveItem
    /// Longest edge to decode photos at, in pixels.
    var maxPixel: CGFloat = 600

    var body: some View {
        if let fileName = item.imageFileName {
            StoredImage(fileName: fileName, maxPixel: maxPixel)
        } else if let style = item.artStyle {
            PlaceholderArt(style: style, seed: item.artSeed)
        } else {
            TextTile(item: item)
        }
    }
}

/// A square (or given-ratio) tile that fills and crops without breaking layout.
struct ItemTile: View {
    let item: SaveItem
    var aspectRatio: CGFloat = 1
    var maxPixel: CGFloat = 500

    var body: some View {
        Color.clear
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay { ItemVisual(item: item, maxPixel: maxPixel) }
            .clipped()
            .contentShape(Rectangle())
    }
}

/// Loads a stored image off the main thread, downsampled and cached.
struct StoredImage: View {
    let fileName: String
    var maxPixel: CGFloat = 600
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Theme.surface
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            }
        }
        .task(id: fileName) {
            let name = fileName
            let pixels = maxPixel
            let loaded = await Task.detached(priority: .userInitiated) {
                ImageStore.image(named: name, maxPixel: pixels)
            }.value
            withAnimation(.easeOut(duration: 0.2)) { image = loaded }
        }
    }
}

/// Notes and links without an image: the words are the visual.
struct TextTile: View {
    let item: SaveItem

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [Theme.raised, Theme.surface], startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: item.kind == .link ? "link" : "text.quote")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                Text(item.displayTitle)
                    .font(.system(.callout, design: .serif))
                    .foregroundStyle(.primary)
                    .lineLimit(5)
                    .multilineTextAlignment(.leading)
            }
            .padding(12)
        }
    }
}

/// Up to four saves as an edge-to-edge mosaic.
struct Mosaic: View {
    let items: [SaveItem]

    var body: some View {
        GeometryReader { proxy in
            let spacing = Theme.tileSpacing
            let visible = Array(items.prefix(3))
            HStack(spacing: spacing) {
                if let first = visible.first {
                    ItemVisual(item: first, maxPixel: 700)
                        .frame(width: visible.count > 1 ? proxy.size.width * 0.62 : proxy.size.width, height: proxy.size.height)
                        .clipped()
                }
                if visible.count > 1 {
                    VStack(spacing: spacing) {
                        ForEach(visible.dropFirst(), id: \.id) { item in
                            ItemVisual(item: item, maxPixel: 400)
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
