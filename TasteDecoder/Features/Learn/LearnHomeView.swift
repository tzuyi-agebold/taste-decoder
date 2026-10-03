import SwiftData
import SwiftUI

/// The learning layer's front door: your core ingredients, what to explore next, and the library.
struct LearnHomeView: View {
    @Environment(LearnLibrary.self) private var library
    @Query(filter: #Predicate<TagEntry> { $0.statusRaw == "confirmed" }) private var confirmedTags: [TagEntry]
    // Imported boards add their tags to the pantry too.
    @Query(filter: #Predicate<TasteCollection> { $0.profileData != nil }) private var importedCollections: [TasteCollection]
    @Query(sort: \LearnCardRecord.updatedAt, order: .reverse) private var records: [LearnCardRecord]

    @Namespace private var learnNamespace
    @State private var path = NavigationPath()
    @State private var query = ""

    private var pantry: [PantryEntry] {
        PantryIndex.build(confirmedTags.compactMap { tag in
            guard let item = tag.item else { return nil }
            return TagUsage(name: tag.name, level: tag.level, itemID: item.id, collectionName: item.collection?.name)
        } + importedCollections.flatMap(\.importedUsages))
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 36) {
                    if query.isEmpty {
                        let entries = pantry
                        coreSection(entries)
                        exploreSection(entries)
                        yourCardsSection
                        ForEach(LearnKind.allCases) { kind in
                            librarySection(kind)
                        }
                    } else {
                        searchResults
                    }
                }
                .padding(.vertical, 8)
                .padding(.bottom, 32)
            }
            .navigationTitle("Learn")
            .searchable(text: $query, prompt: "A person, style or term")
            .onSubmit(of: .search) {
                guard let name = query.nilIfBlank else { return }
                path.append(LearnRoute(name: name.trimmingCharacters(in: .whitespacesAndNewlines), context: "search"))
            }
            .tasteDestinations(learnNamespace)
        }
    }

    // MARK: Sections

    @ViewBuilder
    private func coreSection(_ entries: [PantryEntry]) -> some View {
        let core = Array(entries.filter { $0.level == .ingredient }.prefix(8))
        if !core.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(title: "Your core ingredients", subtitle: "The words your taste keeps reaching for.")
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(core) { entry in
                        LearnChip(name: entry.name, context: "core", style: .confirmed, count: "\(entry.itemCount)")
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    @ViewBuilder
    private func exploreSection(_ entries: [PantryEntry]) -> some View {
        let links = exploreLinks(entries)
        if !links.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(title: "Explore next", subtitle: "Branches from the ingredients you already love.")
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(links, id: \.self) { link in
                        LearnChip(name: link.name, context: "explore", symbol: link.kind.symbol)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    @ViewBuilder
    private var yourCardsSection: some View {
        let cards = records.compactMap(\.content)
        if !cards.isEmpty {
            carousel(title: "Written for you", subtitle: "Cards Claude wrote or you edited.", cards: Array(cards.prefix(12)))
        }
    }

    private func librarySection(_ kind: LearnKind) -> some View {
        carousel(title: kind.pluralLabel, subtitle: nil, cards: library.cards(of: kind))
    }

    private func carousel(title: String, subtitle: String?, cards: [LearnCardContent]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: title, subtitle: subtitle)
                .padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(cards, id: \.title) { card in
                        LibraryCard(card: card)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, 20, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
        }
    }

    @ViewBuilder
    private var searchResults: some View {
        let matches = library.search(query)
        let pantryMatches = pantry.filter { $0.key.contains(TagText.key(query)) }
        VStack(alignment: .leading, spacing: 24) {
            NavigationLink(value: LearnRoute(name: query.trimmingCharacters(in: .whitespacesAndNewlines), context: "search")) {
                HStack(spacing: 12) {
                    Image(systemName: "sparkle.magnifyingglass")
                        .foregroundStyle(Theme.accent)
                    Text("Look up “\(query)”")
                        .font(.body.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
                .padding(16)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(PressableStyle())

            if !pantryMatches.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Eyebrow(text: "In your pantry")
                    FlowLayout(spacing: 8, lineSpacing: 8) {
                        ForEach(pantryMatches.prefix(12)) { entry in
                            LearnChip(name: entry.name, context: "search-pantry", count: "\(entry.itemCount)", symbol: entry.level.symbol)
                        }
                    }
                }
            }

            if !matches.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Eyebrow(text: "In the library")
                    ForEach(matches.prefix(20), id: \.title) { card in
                        NavigationLink(value: LearnRoute(name: card.title, context: "search-library")) {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: card.kind.symbol)
                                    .foregroundStyle(Theme.accent)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(card.title).font(.body.weight(.semibold))
                                    Text(card.summary)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: Helpers

    /// Related topics from your top ingredients' cards that aren't in your pantry yet.
    private func exploreLinks(_ entries: [PantryEntry]) -> [LearnLink] {
        let have = Set(entries.map(\.key))
        var seen = Set<String>()
        var links: [LearnLink] = []
        for entry in entries.prefix(8) {
            let card = records.first(where: { $0.key == entry.key })?.content ?? library.card(for: entry.key)
            for link in card?.related ?? [] {
                let key = TagText.key(link.name)
                guard !have.contains(key), seen.insert(key).inserted else { continue }
                links.append(link)
            }
        }
        return Array(links.prefix(12))
    }
}

private struct LibraryCard: View {
    let card: LearnCardContent
    @Environment(\.learnNamespace) private var namespace

    var body: some View {
        let route = LearnRoute(name: card.title, context: "library")
        NavigationLink(value: route) {
            VStack(alignment: .leading, spacing: 10) {
                PlaceholderArt(style: .poster, seed: StableHash.int(card.title))
                    .frame(width: 200, height: 130)
                    .overlay(alignment: .topLeading) {
                        Image(systemName: card.kind.symbol)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(8)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .zoomSource(id: route.sourceID, in: namespace)
                VStack(alignment: .leading, spacing: 3) {
                    Text(card.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(card.summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(width: 200, alignment: .leading)
        }
        .buttonStyle(PressableStyle())
    }
}
