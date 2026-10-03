import Foundation

// Pure, Foundation-only taste logic: tag levels, normalization, distillation,
// taste statements and comparison. No SwiftUI or SwiftData here so it can be
// unit-tested anywhere (see Package.swift and Tests/TasteCoreTests).

// MARK: - The articulation ladder

/// The three rungs of the articulation ladder, from universal to technical.
enum TagLevel: String, CaseIterable, Codable, Identifiable, Sendable {
    case feeling
    case reference
    case ingredient

    var id: String { rawValue }

    /// Short label for segmented controls.
    var title: String {
        switch self {
        case .feeling: "Feeling"
        case .reference: "Reference"
        case .ingredient: "Ingredients"
        }
    }

    /// Plural section title.
    var pluralTitle: String {
        switch self {
        case .feeling: "Feelings"
        case .reference: "References"
        case .ingredient: "Ingredients"
        }
    }

    /// Singular noun used in placeholders ("Add a feeling").
    var noun: String {
        switch self {
        case .feeling: "feeling"
        case .reference: "reference"
        case .ingredient: "ingredient"
        }
    }

    /// The question each rung asks. Teach by doing, not by explaining.
    var question: String {
        switch self {
        case .feeling: "What does it feel like?"
        case .reference: "Is there a reference that captures it?"
        case .ingredient: "What are the ingredients?"
        }
    }

    var hint: String {
        switch self {
        case .feeling: "cozy, uncomfortable, electric…"
        case .reference: "a Michel Gondry movie, 90s skate zine…"
        case .ingredient: "flash lighting, toasted oak, brushed drums…"
        }
    }

    var symbol: String {
        switch self {
        case .feeling: "heart"
        case .reference: "quote.opening"
        case .ingredient: "eyedropper"
        }
    }

    var next: TagLevel? {
        switch self {
        case .feeling: .reference
        case .reference: .ingredient
        case .ingredient: nil
        }
    }
}

enum TagStatus: String, Codable, Sendable {
    /// Proposed by AI; never counts until the user confirms it.
    case suggested
    case confirmed
    case rejected
}

enum TagSource: String, Codable, Sendable {
    case user
    case ai
}

// MARK: - Normalization

enum TagText {
    /// Matching key: case-, width- and diacritic-insensitive, dashes unified,
    /// whitespace collapsed, surrounding punctuation trimmed.
    /// "  Harsh  Flash Lighting. " and "harsh flash lighting" share a key.
    static func key(_ raw: String) -> String {
        let folded = raw
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                     locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
        let unifiedDashes = folded.map { character -> Character in
            switch character {
            case "\u{2010}", "\u{2011}", "\u{2012}", "\u{2013}", "\u{2014}", "\u{2212}": "-"
            case "\u{2018}", "\u{2019}": "'"
            default: character
            }
        }
        let collapsed = String(unifiedDashes)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        var trimSet = CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines)
        trimSet.remove(charactersIn: "%#+'")
        return collapsed.trimmingCharacters(in: trimSet)
    }

    /// Display cleanup: trims, collapses whitespace, caps length. Keeps the user's casing.
    static func clean(_ raw: String, maxLength: Int = 60) -> String {
        let collapsed = raw
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:").union(.whitespacesAndNewlines))
        return String(collapsed.prefix(maxLength))
    }
}

// MARK: - Distillation

struct TagSnapshot: Hashable, Sendable {
    let name: String
    let level: TagLevel
}

/// A save reduced to what distillation needs: its confirmed tags.
struct ItemSnapshot: Sendable {
    let id: UUID
    let tags: [TagSnapshot]

    var isDecoded: Bool { !tags.isEmpty }
}

/// How often one tag recurs across a collection.
struct TagCount: Identifiable, Hashable, Sendable {
    let key: String
    let name: String
    let level: TagLevel
    /// Number of saves carrying this tag.
    let count: Int
    /// Number of saves in the collection.
    let total: Int

    var id: String { "\(level.rawValue):\(key)" }
    var fraction: Double { total == 0 ? 0 : Double(count) / Double(total) }
    var ratioText: String { "\(count) of \(total)" }
}

struct Distillation: Sendable {
    let totalItems: Int
    let decodedItems: Int
    let feelings: [TagCount]
    let references: [TagCount]
    let ingredients: [TagCount]

    static let empty = Distillation(totalItems: 0, decodedItems: 0, feelings: [], references: [], ingredients: [])

    func counts(for level: TagLevel) -> [TagCount] {
        switch level {
        case .feeling: feelings
        case .reference: references
        case .ingredient: ingredients
        }
    }

    /// Tags that show up in two or more saves. With a single decoded save, all of its tags count.
    func recurring(_ level: TagLevel) -> [TagCount] {
        let all = counts(for: level)
        if decodedItems <= 1 { return all }
        return all.filter { $0.count >= 2 }
    }

    /// The 3–5 ingredients that define this collection. Falls back to the top single
    /// mentions when nothing recurs yet (see `isTentative`).
    var signatureIngredients: [TagCount] {
        let recurring = recurring(.ingredient)
        if recurring.isEmpty { return Array(ingredients.prefix(3)) }
        return Array(recurring.prefix(5))
    }

    var leadFeeling: TagCount? { recurring(.feeling).first ?? feelings.first }
    var leadReference: TagCount? { recurring(.reference).first ?? references.first }

    /// True when there isn't enough evidence yet to call it a pattern.
    var isTentative: Bool { decodedItems < 3 || recurring(.ingredient).count < 3 }

    var hasContent: Bool { !feelings.isEmpty || !ingredients.isEmpty || !references.isEmpty }

    /// Stable fingerprint of what a taste statement is built from. When it changes,
    /// a previously written statement is out of date.
    var signature: String {
        let parts = [leadFeeling?.key ?? "-"]
            + [leadReference?.key ?? "-"]
            + signatureIngredients.map(\.key)
        return parts.joined(separator: "|")
    }
}

enum Distiller {
    static func distill(_ items: [ItemSnapshot]) -> Distillation {
        let total = items.count
        let decoded = items.filter(\.isDecoded).count

        func tally(_ level: TagLevel) -> [TagCount] {
            // key -> (item ids, name variants in order of appearance with counts)
            var itemsByKey: [String: Set<UUID>] = [:]
            var variants: [String: [(name: String, uses: Int)]] = [:]
            var firstSeen: [String: Int] = [:]
            var order = 0

            for item in items {
                for tag in item.tags where tag.level == level {
                    let key = TagText.key(tag.name)
                    guard !key.isEmpty else { continue }
                    itemsByKey[key, default: []].insert(item.id)
                    if firstSeen[key] == nil {
                        firstSeen[key] = order
                        order += 1
                    }
                    let name = TagText.clean(tag.name)
                    if let index = variants[key]?.firstIndex(where: { $0.name == name }) {
                        variants[key]?[index].uses += 1
                    } else {
                        variants[key, default: []].append((name, 1))
                    }
                }
            }

            return itemsByKey.map { key, ids in
                // Most-used spelling wins; ties go to the first one typed.
                let name = variants[key]?.max(by: { $0.uses < $1.uses })?.name ?? key
                return TagCount(key: key, name: name, level: level, count: ids.count, total: total)
            }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return (firstSeen[lhs.key] ?? 0) < (firstSeen[rhs.key] ?? 0)
            }
        }

        return Distillation(
            totalItems: total,
            decodedItems: decoded,
            feelings: tally(.feeling),
            references: tally(.reference),
            ingredients: tally(.ingredient)
        )
    }
}

// MARK: - Taste statements

/// The formula behind every statement: feeling + references + ingredients.
struct TasteFormula: Sendable {
    let feeling: String?
    let references: [String]
    let ingredients: [String]
}

enum TasteStatement {
    static func formula(_ distillation: Distillation) -> TasteFormula {
        TasteFormula(
            feeling: distillation.leadFeeling?.name,
            references: Array(distillation.recurring(.reference).prefix(2).map(\.name)),
            ingredients: distillation.signatureIngredients.map(\.name)
        )
    }

    /// Deterministic statement in the shape "I like [domain] that [verb] [feeling] — [ingredients]."
    /// Used offline and as the starting point Claude polishes. Returns nil when nothing is decoded.
    static func template(domain: String, verb: String = "feel", distillation: Distillation) -> String? {
        let formula = formula(distillation)
        let subject = domain.trimmingCharacters(in: .whitespaces).isEmpty ? "things" : domain.trimmingCharacters(in: .whitespaces)
        let sense = verb.trimmingCharacters(in: .whitespaces).isEmpty ? "feel" : verb.trimmingCharacters(in: .whitespaces)
        let ingredients = formula.ingredients

        switch (formula.feeling, ingredients.isEmpty) {
        case let (feeling?, false):
            return "I like \(subject) that \(sense) \(feeling) — \(ingredients.joined(separator: ", "))."
        case let (feeling?, true):
            return "I like \(subject) that \(sense) \(feeling)."
        case (nil, false):
            return "I like \(subject) with \(ingredients.joined(separator: ", "))."
        case (nil, true):
            return nil
        }
    }

    /// Headline hook for the distillation reveal: "9 of 10 saves share harsh flash lighting."
    /// `noun` names the items: saves, or pins for an imported board.
    static func headline(_ distillation: Distillation, noun: (one: String, many: String) = ("save", "saves")) -> String? {
        guard let top = distillation.signatureIngredients.first else { return nil }
        if top.total == 1 { return "One \(noun.one) so far — it leads with \(top.name)." }
        if top.count == top.total { return "All \(top.total) \(noun.many) share \(top.name)." }
        return "\(top.count) of \(top.total) \(noun.many) share \(top.name)."
    }
}

// MARK: - Comparison

/// A tag both collections share: the common ground.
struct CommonGround: Identifiable, Hashable, Sendable {
    let key: String
    let name: String
    let level: TagLevel
    let countA: Int
    let totalA: Int
    let countB: Int
    let totalB: Int

    var id: String { key }
    /// How strongly both sides lean on it (the weaker side's share).
    var strength: Double {
        let a = totalA == 0 ? 0 : Double(countA) / Double(totalA)
        let b = totalB == 0 ? 0 : Double(countB) / Double(totalB)
        return min(a, b)
    }
}

struct Comparison: Sendable {
    let common: [CommonGround]
    let onlyA: [TagCount]
    let onlyB: [TagCount]

    /// Share of all distinct tags that both sides have (Jaccard index).
    var overlap: Double {
        let union = common.count + onlyA.count + onlyB.count
        return union == 0 ? 0 : Double(common.count) / Double(union)
    }

    func common(_ level: TagLevel) -> [CommonGround] { common.filter { $0.level == level } }

    /// "Reds I Love and Rooms both feel warm and cozy — because of leather."
    func sentence(nameA: String, nameB: String) -> String {
        guard !common.isEmpty else {
            let a = onlyA.first?.name ?? "their own thing"
            let b = onlyB.first?.name ?? "their own thing"
            return "No common ground yet — \(nameA) is about \(a), \(nameB) is about \(b). That's a conversation too."
        }
        let feelings = common(.feeling).prefix(2).map(\.name)
        let because = (common(.ingredient) + common(.reference)).prefix(3).map(\.name)

        if !feelings.isEmpty {
            var sentence = "\(nameA) and \(nameB) both feel \(Self.list(feelings))"
            if !because.isEmpty { sentence += " — because of \(Self.list(because))" }
            return sentence + "."
        }
        return "\(nameA) and \(nameB) meet at \(Self.list(because))."
    }

    static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return "\(items[0]) and \(items[1])"
        default: return items.dropLast().joined(separator: ", ") + " and " + items.last!
        }
    }
}

enum Comparer {
    /// Matches tags by key regardless of level, so "late-night" as a feeling in one
    /// collection meets "late-night" as a reference in the other.
    static func compare(_ a: Distillation, _ b: Distillation) -> Comparison {
        let allA = a.feelings + a.references + a.ingredients
        let allB = b.feelings + b.references + b.ingredients
        let indexB = Dictionary(allB.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        let keysA = Set(allA.map(\.key))

        var seen = Set<String>()
        var common: [CommonGround] = []
        for tag in allA where !seen.contains(tag.key) {
            seen.insert(tag.key)
            guard let match = indexB[tag.key] else { continue }
            common.append(CommonGround(
                key: tag.key, name: tag.name, level: tag.level,
                countA: tag.count, totalA: tag.total,
                countB: match.count, totalB: match.total
            ))
        }
        common.sort { lhs, rhs in
            if lhs.strength != rhs.strength { return lhs.strength > rhs.strength }
            return (lhs.countA + lhs.countB) > (rhs.countA + rhs.countB)
        }

        let commonKeys = Set(common.map(\.key))
        let onlyA = allA.filter { !commonKeys.contains($0.key) }.uniqued().sorted { $0.fraction > $1.fraction }
        let onlyB = allB.filter { !commonKeys.contains($0.key) && !keysA.contains($0.key) }.uniqued().sorted { $0.fraction > $1.fraction }
        return Comparison(common: common, onlyA: onlyA, onlyB: onlyB)
    }
}

private extension Array where Element == TagCount {
    /// Keeps the first occurrence of each key.
    func uniqued() -> [TagCount] {
        var seen = Set<String>()
        return filter { seen.insert($0.key).inserted }
    }
}
