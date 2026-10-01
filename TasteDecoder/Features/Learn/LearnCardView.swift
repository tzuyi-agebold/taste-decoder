import SwiftData
import SwiftUI

/// The person, style or term behind a tag — with examples, related topics,
/// and a closing line tying it back to your own saves.
struct LearnCardView: View {
    let route: LearnRoute

    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(LearnLibrary.self) private var library
    @Query private var records: [LearnCardRecord]
    @Query(filter: #Predicate<TagEntry> { $0.statusRaw == "confirmed" }) private var confirmedTags: [TagEntry]
    @Query private var allItems: [SaveItem]

    @State private var generating = false
    @State private var errorMessage: String?
    @State private var showEditor = false
    @State private var showSettings = false

    private enum Origin {
        case library, generated, edited

        var footnote: String {
            switch self {
            case .library: "From the Taste Decoder library."
            case .generated: "Written by Claude for your pantry. Check facts that matter."
            case .edited: "Edited by you."
            }
        }
    }

    private var key: String { TagText.key(route.name) }

    /// Records are saved under the library card's title key when there is one, so aliases share edits.
    private var canonicalKey: String {
        library.card(for: key).map { TagText.key($0.title) } ?? key
    }

    private var record: LearnCardRecord? {
        records.first { $0.key == canonicalKey } ?? records.first { $0.key == key }
    }

    private var resolved: (card: LearnCardContent, origin: Origin)? {
        if let record, let content = record.content {
            return (content, record.origin == "edited" ? .edited : .generated)
        }
        if let bundled = library.card(for: key) { return (bundled, .library) }
        return nil
    }

    var body: some View {
        Group {
            if let resolved {
                cardBody(resolved.card, origin: resolved.origin)
            } else if generating {
                GeneratingView(name: route.name)
            } else if !settings.hasAPIKey {
                ContentUnavailableView {
                    Label("No card for “\(route.name)” yet", systemImage: "character.book.closed")
                } description: {
                    Text("Add your Claude API key and Taste Decoder will write one — who or what it is, examples, and where to go next.")
                } actions: {
                    Button("Open Settings") { showSettings = true }
                        .buttonStyle(.borderedProminent)
                }
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("Couldn't write this card", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Try again") { Task { await generate(force: true) } }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                GeneratingView(name: route.name)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if let resolved {
                        Button {
                            showEditor = true
                        } label: {
                            Label("Edit card", systemImage: "pencil")
                        }
                        if settings.hasAPIKey {
                            Button {
                                Task { await generate(force: true) }
                            } label: {
                                Label(resolved.origin == .library ? "Rewrite with Claude" : "Regenerate", systemImage: "sparkles")
                            }
                        }
                        if record != nil {
                            Button(role: .destructive) {
                                resetToOriginal()
                            } label: {
                                Label(library.card(for: key) != nil ? "Restore library version" : "Delete card", systemImage: "arrow.uturn.backward")
                            }
                        }
                    }
                } label: {
                    Label("Card options", systemImage: "ellipsis.circle")
                }
                .disabled(resolved == nil)
            }
        }
        .task(id: key) { await generate(force: false) }
        .sheet(isPresented: $showEditor) {
            if let resolved {
                LearnCardEditor(card: resolved.card) { edited in
                    save(edited, origin: "edited")
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    // MARK: Card

    private func cardBody(_ card: LearnCardContent, origin: Origin) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                hero(card)

                VStack(alignment: .leading, spacing: 30) {
                    section(card.kind.summaryHeading) {
                        Text(card.summary)
                            .font(.title3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if !card.characteristics.isEmpty {
                        section(card.kind.characteristicsHeading) {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(Array(card.characteristics.enumerated()), id: \.offset) { _, line in
                                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                                        Circle()
                                            .fill(Theme.accent)
                                            .frame(width: 6, height: 6)
                                            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
                                        Text(line)
                                            .font(.body)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)

                if !card.examples.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Eyebrow(text: card.kind.examplesHeading)
                            .padding(.horizontal, 20)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 12) {
                                ForEach(Array(card.examples.enumerated()), id: \.offset) { _, example in
                                    ExampleCard(example: example)
                                }
                            }
                            .scrollTargetLayout()
                        }
                        .contentMargins(.horizontal, 20, for: .scrollContent)
                        .scrollTargetBehavior(.viewAligned)
                    }
                }

                VStack(alignment: .leading, spacing: 30) {
                    if !card.encounter.isEmpty {
                        section("In the wild") {
                            Text(card.encounter)
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    whyItMatters(card)

                    if !card.related.isEmpty {
                        section("Explore next") {
                            FlowLayout(spacing: 8, lineSpacing: 8) {
                                ForEach(card.related, id: \.self) { link in
                                    LearnChip(name: link.name, context: "related-\(canonicalKey)", symbol: link.kind.symbol)
                                }
                            }
                        }
                    }

                    Text(origin.footnote)
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 40)
        }
        .overlay(alignment: .top) {
            if generating {
                Label("Rewriting…", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 8)
            }
        }
    }

    private func hero(_ card: LearnCardContent) -> some View {
        ZStack(alignment: .bottomLeading) {
            PlaceholderArt(style: heroStyle(card), seed: StableHash.int(card.title))
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 8) {
                Label(card.kind.label, systemImage: card.kind.symbol)
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.accent, in: Capsule())
                Text(card.title)
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                if !card.era.isEmpty {
                    Text(card.era)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .padding(20)
        }
        .frame(height: 280)
        .clipped()
        .environment(\.colorScheme, .dark)
    }

    /// Visual topics borrow the art style of the collections they come from.
    private func heroStyle(_ card: LearnCardContent) -> ArtStyle {
        let keys = Set(card.keys + [key])
        let styles = confirmedTags.filter { keys.contains($0.key) }.compactMap { $0.item?.artStyle }
        if let common = Dictionary(grouping: styles, by: { $0 }).max(by: { $0.value.count < $1.value.count })?.key {
            return common
        }
        return .poster
    }

    private func whyItMatters(_ card: LearnCardContent) -> some View {
        let personal = PantryIndex.whyItMattersToYou(keys: card.keys + [key], title: route.name,
                                                     entries: pantryEntries, collectionSizes: collectionSizes)
        return VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Why it matters to you", color: Theme.accent)
            Text(personal)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            if !card.whyItMatters.isEmpty {
                Text(card.whyItMatters)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay(alignment: .leading) {
            Capsule()
                .fill(Theme.accent)
                .frame(width: 4)
                .padding(.vertical, 18)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: title)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Personal context

    private var pantryEntries: [PantryEntry] {
        PantryIndex.build(confirmedTags.compactMap { tag in
            guard let item = tag.item else { return nil }
            return TagUsage(name: tag.name, level: tag.level, itemID: item.id, collectionName: item.collection?.name)
        })
    }

    private var collectionSizes: [String: Int] {
        var sizes: [String: Int] = [:]
        for item in allItems {
            sizes[item.collection?.name ?? PantryIndex.unsortedName, default: 0] += 1
        }
        return sizes
    }

    /// e.g. "an ingredient in Uncomfy (6 saves)"
    private var usageDescription: String? {
        let keys = Set([key, canonicalKey])
        guard let entry = pantryEntries.first(where: { keys.contains($0.key) }) else { return nil }
        let collections = entry.collectionNames.prefix(3).joined(separator: ", ")
        return "a \(entry.level.noun) in \(collections) (\(entry.itemCount) \(entry.itemCount == 1 ? "save" : "saves"))"
    }

    private var neighbors: [String] {
        let keys = Set([key, canonicalKey])
        let items = confirmedTags.filter { keys.contains($0.key) }.compactMap(\.item)
        var counts: [String: Int] = [:]
        for item in items {
            for tag in item.confirmedTags where !keys.contains(tag.key) { counts[tag.name, default: 0] += 1 }
        }
        return counts.sorted { $0.value > $1.value }.prefix(10).map(\.key)
    }

    // MARK: Actions

    private func generate(force: Bool) async {
        guard force || resolved == nil, !generating else { return }
        guard let client = try? settings.client() else { return }
        generating = true
        errorMessage = nil
        do {
            let card = try await LearnCardGenerator.generate(topic: resolved?.card.title ?? route.name, usage: usageDescription,
                                                             neighbors: neighbors, client: client)
            withAnimation(Theme.spring) { save(card, origin: "generated") }
        } catch {
            errorMessage = error.localizedDescription
        }
        generating = false
    }

    private func save(_ card: LearnCardContent, origin: String) {
        if let record {
            record.update(card, origin: origin)
        } else {
            context.insert(LearnCardRecord(key: canonicalKey, content: card, origin: origin))
        }
        try? context.save()
    }

    private func resetToOriginal() {
        guard let record else { return }
        withAnimation(Theme.spring) { context.delete(record) }
        try? context.save()
    }
}

// MARK: - Pieces

private struct ExampleCard: View {
    let example: LearnExample

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PlaceholderArt(style: .poster, seed: StableHash.int(example.title))
                .frame(width: 220, height: 140)
                .overlay(alignment: .bottomLeading) {
                    Text(example.title)
                        .font(.system(.headline, design: .serif))
                        .foregroundStyle(.white)
                        .lineLimit(3)
                        .padding(12)
                        .shadow(color: .black.opacity(0.4), radius: 6)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text(example.detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 220, alignment: .topLeading)
    }
}

private struct GeneratingView: View {
    let name: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.largeTitle)
                .foregroundStyle(Theme.accent)
                .symbolEffect(.pulse)
            Text("Writing a card about “\(name)”…")
                .font(.headline)
            Text("Who or what it is, how to spot it, and where to go next.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
