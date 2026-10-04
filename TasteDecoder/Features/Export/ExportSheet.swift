import SwiftData
import SwiftUI

enum TasteExport {
    /// A one-paragraph taste statement you can paste anywhere.
    static func paragraph(collection: TasteCollection, distillation: Distillation) -> String {
        let statement = collection.currentStatement(for: distillation).text ?? "Still decoding."
        var sentences = ["My taste in \(collection.domain), from my “\(collection.name)” collection: \(statement)"]
        let ingredients = distillation.signatureIngredients.map { "\($0.name) (\($0.ratioText))" }
        if !ingredients.isEmpty {
            sentences.append("The ingredients that keep showing up: \(ingredients.joined(separator: ", ")).")
        }
        let feelings = distillation.recurring(.feeling).prefix(3).map(\.name)
        if !feelings.isEmpty {
            sentences.append("It feels \(Comparison.list(Array(feelings))).")
        }
        let references = distillation.references.prefix(3).map(\.name)
        if !references.isEmpty {
            sentences.append("References: \(references.joined(separator: ", ")).")
        }
        return sentences.joined(separator: " ")
    }
}

/// Share a taste card image or the one-paragraph statement.
struct ExportSheet: View {
    let collection: TasteCollection

    @Environment(\.dismiss) private var dismiss
    @Query private var allItems: [SaveItem]

    @State private var format: Format = .card
    @State private var rendered: UIImage?
    @State private var copiedTick = 0

    enum Format: String, CaseIterable, Identifiable {
        case card, text
        var id: String { rawValue }
        var title: String { self == .card ? "Card" : "Text" }
    }

    var body: some View {
        let items = allItems.filter { $0.collection == collection }.sorted { $0.createdAt > $1.createdAt }
        let distillation = collection.effectiveDistillation(items: items)
        let paragraph = TasteExport.paragraph(collection: collection, distillation: distillation)

        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Picker("Format", selection: $format.animation(Theme.spring)) {
                        ForEach(Format.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if format == .card {
                        Group {
                            if let rendered {
                                Image(uiImage: rendered)
                                    .resizable()
                                    .scaledToFit()
                                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                                    .shadow(color: .black.opacity(0.4), radius: 24, y: 12)
                                    .transition(.scale(scale: 0.96).combined(with: .opacity))
                            } else {
                                ProgressView()
                                    .frame(maxWidth: .infinity, minHeight: 420)
                            }
                        }
                        .padding(.horizontal, 12)

                        if let rendered {
                            ShareLink(item: Image(uiImage: rendered),
                                      preview: SharePreview("\(collection.name) — taste card", image: Image(uiImage: rendered))) {
                                Label("Share card", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(PrimaryButtonStyle())
                        }
                    } else {
                        Text(paragraph)
                            .font(.system(.title3, design: .serif))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .cardBackground()

                        HStack(spacing: 12) {
                            Button {
                                UIPasteboard.general.string = paragraph
                                copiedTick += 1
                            } label: {
                                Label(copiedTick > 0 ? "Copied" : "Copy", systemImage: copiedTick > 0 ? "checkmark" : "doc.on.doc")
                                    .frame(minHeight: 52)
                                    .padding(.horizontal, 8)
                            }
                            .buttonStyle(SecondaryButtonStyle())

                            ShareLink(item: paragraph) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(PrimaryButtonStyle())
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("Share your taste")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                let image = renderCard(items: items, distillation: distillation)
                withAnimation(Theme.spring) { rendered = image }
            }
            .sensoryFeedback(.success, trigger: copiedTick)
        }
        .presentationDetents([.large])
    }

    @MainActor
    private func renderCard(items: [SaveItem], distillation: Distillation) -> UIImage? {
        let fromSaves: [TasteCardView.Visual] = items.compactMap { item in
            if let fileName = item.imageFileName, let image = ImageStore.image(named: fileName, maxPixel: 700) {
                return .photo(image)
            }
            if let style = item.artStyle { return .art(style, item.artSeed) }
            return nil
        }
        let covers: [TasteCardView.Visual] = collection.coverImageNames.compactMap { name in
            ImageStore.image(named: name, maxPixel: 700).map(TasteCardView.Visual.photo)
        }
        let visuals = fromSaves + covers
        let card = TasteCardView(
            name: collection.name,
            domain: collection.domain,
            statement: collection.currentStatement(for: distillation).text ?? "Still decoding.",
            ingredients: Array(distillation.signatureIngredients.prefix(4)),
            references: Array(distillation.references.prefix(2).map(\.name)),
            visuals: Array(visuals.prefix(3))
        )
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        return renderer.uiImage
    }
}

/// The shareable card. Fixed dark palette so it looks the same wherever it lands.
struct TasteCardView: View {
    enum Visual {
        case photo(UIImage)
        case art(ArtStyle, Int)
    }

    let name: String
    let domain: String
    let statement: String
    let ingredients: [TagCount]
    let references: [String]
    let visuals: [Visual]

    private let lime = Color(hex: 0xCBFF3D)
    private let ink = Color(hex: 0x0B0B0C)
    private let track = Color(hex: 0x26262A)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 2) {
                ForEach(Array(visuals.enumerated()), id: \.offset) { _, visual in
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(height: 150)
                        .overlay { view(for: visual) }
                        .clipped()
                }
            }
            .frame(height: visuals.isEmpty ? 0 : 150)

            VStack(alignment: .leading, spacing: 18) {
                Text("MY TASTE IN \(domain.uppercased())")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(lime)

                Text(statement)
                    .font(.system(size: 24, weight: .medium, design: .serif))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(ingredients) { count in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(count.name)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.white)
                                Spacer()
                                Text(count.ratioText)
                                    .font(.system(size: 12, weight: .semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(lime)
                            }
                            GeometryReader { proxy in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(track)
                                    Capsule().fill(lime).frame(width: max(proxy.size.width * count.fraction, 4))
                                }
                            }
                            .frame(height: 4)
                        }
                    }
                }

                if !references.isEmpty {
                    Text("Feels like " + references.joined(separator: ", "))
                        .font(.system(size: 13, weight: .regular, design: .serif))
                        .italic()
                        .foregroundStyle(.white.opacity(0.7))
                }

                Spacer(minLength: 0)

                HStack {
                    Text(name)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("Taste Decoder")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(lime)
                }
            }
            .padding(24)
        }
        .frame(width: 360, height: 560)
        .background(ink)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private func view(for visual: Visual) -> some View {
        switch visual {
        case let .photo(image):
            Image(uiImage: image).resizable().scaledToFill()
        case let .art(style, seed):
            PlaceholderArt(style: style, seed: seed, rendersAsynchronously: false)
        }
    }
}
