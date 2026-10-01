import Foundation

// Learn cards and the personal pantry. Foundation-only, like TasteCore.swift.

// MARK: - Learn cards

enum LearnKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case person
    case style
    case term

    var id: String { rawValue }

    var label: String {
        switch self {
        case .person: "Person"
        case .style: "Style"
        case .term: "Term"
        }
    }

    var pluralLabel: String {
        switch self {
        case .person: "People"
        case .style: "Styles & movements"
        case .term: "Terms & techniques"
        }
    }

    var symbol: String {
        switch self {
        case .person: "person.crop.circle"
        case .style: "paintpalette"
        case .term: "character.book.closed"
        }
    }

    var summaryHeading: String {
        switch self {
        case .person: "Who"
        case .style: "What it is"
        case .term: "What it means"
        }
    }

    var characteristicsHeading: String {
        switch self {
        case .person: "Signature moves"
        case .style: "Defining characteristics"
        case .term: "How to spot it"
        }
    }

    var examplesHeading: String {
        switch self {
        case .person: "Signature works"
        case .style: "Canonical examples"
        case .term: "Examples"
        }
    }
}

struct LearnExample: Codable, Hashable, Sendable {
    var title: String
    var detail: String
}

struct LearnLink: Codable, Hashable, Sendable {
    var name: String
    var kind: LearnKind
}

struct LearnCardContent: Codable, Hashable, Sendable {
    var title: String
    var kind: LearnKind
    var aliases: [String]
    /// One-line bio (person), plain-language definition (style) or meaning (term).
    var summary: String
    /// Era / movement / when it emerged. Empty when not applicable.
    var era: String
    var characteristics: [String]
    var examples: [LearnExample]
    /// Where you'd encounter it in the wild (mostly for terms).
    var encounter: String
    /// Why it matters to someone whose taste includes it (general; the personal line is computed live).
    var whyItMatters: String
    var related: [LearnLink]

    init(title: String, kind: LearnKind, aliases: [String] = [], summary: String, era: String = "",
         characteristics: [String] = [], examples: [LearnExample] = [], encounter: String = "",
         whyItMatters: String = "", related: [LearnLink] = []) {
        self.title = title
        self.kind = kind
        self.aliases = aliases
        self.summary = summary
        self.era = era
        self.characteristics = characteristics
        self.examples = examples
        self.encounter = encounter
        self.whyItMatters = whyItMatters
        self.related = related
    }

    // Tolerant decoding so hand-written JSON can omit empty fields.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decode(String.self, forKey: .title)
        kind = try c.decodeIfPresent(LearnKind.self, forKey: .kind) ?? .term
        aliases = try c.decodeIfPresent([String].self, forKey: .aliases) ?? []
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        era = try c.decodeIfPresent(String.self, forKey: .era) ?? ""
        characteristics = try c.decodeIfPresent([String].self, forKey: .characteristics) ?? []
        examples = try c.decodeIfPresent([LearnExample].self, forKey: .examples) ?? []
        encounter = try c.decodeIfPresent(String.self, forKey: .encounter) ?? ""
        whyItMatters = try c.decodeIfPresent(String.self, forKey: .whyItMatters) ?? ""
        related = try c.decodeIfPresent([LearnLink].self, forKey: .related) ?? []
    }

    /// Every key this card answers to.
    var keys: [String] { ([title] + aliases).map(TagText.key) }
}

// MARK: - Pantry

/// One confirmed tag occurrence, flattened from storage.
struct TagUsage: Sendable {
    let name: String
    let level: TagLevel
    let itemID: UUID
    let collectionName: String?
}

/// A confirmed ingredient (or feeling, or reference) in the personal glossary.
struct PantryEntry: Identifiable, Hashable, Sendable {
    let key: String
    let level: TagLevel
    let name: String
    /// Distinct saves carrying it.
    let itemCount: Int
    /// Collection name -> saves in that collection carrying it.
    let collections: [String: Int]

    var id: String { "\(level.rawValue):\(key)" }

    /// Collections ordered by how much they use this tag.
    var collectionNames: [String] {
        collections.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.map(\.key)
    }
}

enum PantryIndex {
    static let unsortedName = "Unsorted"

    static func build(_ usages: [TagUsage]) -> [PantryEntry] {
        struct Accumulator {
            var names: [String: Int] = [:]
            var firstName: String
            var items = Set<UUID>()
            var collections: [String: Set<UUID>] = [:]
        }
        var byID: [String: Accumulator] = [:]
        var order: [String] = []

        for usage in usages {
            let key = TagText.key(usage.name)
            guard !key.isEmpty else { continue }
            let id = "\(usage.level.rawValue):\(key)"
            let name = TagText.clean(usage.name)
            if byID[id] == nil {
                byID[id] = Accumulator(firstName: name)
                order.append(id)
            }
            byID[id]?.names[name, default: 0] += 1
            byID[id]?.items.insert(usage.itemID)
            byID[id]?.collections[usage.collectionName ?? unsortedName, default: []].insert(usage.itemID)
        }

        return order.compactMap { id -> PantryEntry? in
            guard let acc = byID[id], let level = TagLevel(rawValue: String(id.prefix(while: { $0 != ":" }))) else { return nil }
            let key = String(id.drop(while: { $0 != ":" }).dropFirst())
            let topCount = acc.names.values.max() ?? 0
            let name = acc.names[acc.firstName] == topCount
                ? acc.firstName
                : (acc.names.filter { $0.value == topCount }.map(\.key).sorted().first ?? acc.firstName)
            return PantryEntry(
                key: key,
                level: level,
                name: name,
                itemCount: acc.items.count,
                collections: acc.collections.mapValues(\.count)
            )
        }
        .sorted { $0.itemCount == $1.itemCount ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending : $0.itemCount > $1.itemCount }
    }

    /// The line that ends every Learn card, tying the topic back to the user's own saves.
    static func whyItMattersToYou(keys: [String], title: String, entries: [PantryEntry], collectionSizes: [String: Int]) -> String {
        let keySet = Set(keys)
        let matches = entries.filter { keySet.contains($0.key) }
        guard !matches.isEmpty else {
            return "It isn't in your saves yet. Explore it — if it clicks, it becomes part of your vocabulary."
        }

        // Distinct saves can't be recovered across levels, so take the strongest level's count.
        let count = matches.map(\.itemCount).max() ?? 0
        var perCollection: [String: Int] = [:]
        for entry in matches {
            for (name, n) in entry.collections { perCollection[name] = max(perCollection[name] ?? 0, n) }
        }
        let ordered = perCollection.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
        let savesWord = count == 1 ? "save" : "saves"
        var line = "You have \(count) \(savesWord) tagged “\(title)”"

        if let top = ordered.first {
            if let size = collectionSizes[top.key], size > 0, top.key != unsortedName {
                line += " — \(top.value) of \(size) in \(top.key)"
            } else if top.key != unsortedName {
                line += " — mostly in \(top.key)"
            }
            if ordered.count > 1 { line += ", plus \(ordered.count - 1) more \(ordered.count == 2 ? "collection" : "collections")" }
        }
        line += "."

        let isCore = ordered.contains { name, n in
            guard let size = collectionSizes[name], size > 0 else { return false }
            return n >= 3 && Double(n) / Double(size) >= 0.4
        } || count >= 6
        if isCore {
            line += " This is a core ingredient of your taste."
        } else if count >= 2 {
            line += " It's a recurring note — name it when you brief someone."
        } else {
            line += " A new note. Save more to see if it sticks."
        }
        return line
    }
}
