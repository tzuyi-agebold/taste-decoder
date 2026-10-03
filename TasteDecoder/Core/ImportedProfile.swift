import Foundation

// Collections imported from elsewhere (a Pinterest board) arrive as a summary — tag counts over
// the pins Claude looked at — rather than as individual saves. These types turn that summary
// into a regular Distillation so statements, Distill and Compare work unchanged.

struct NamedCount: Codable, Hashable, Sendable {
    var name: String
    var count: Int
}

struct ImportedProfile: Codable, Hashable, Sendable {
    /// Items Claude actually looked at; the denominator for every count.
    var analyzedItems: Int
    /// Items in the source (e.g. pins on the board), for "From 20 of 143 pins".
    var totalItems: Int
    var feelings: [NamedCount]
    var references: [NamedCount]
    var ingredients: [NamedCount]

    func counts(for level: TagLevel) -> [NamedCount] {
        switch level {
        case .feeling: feelings
        case .reference: references
        case .ingredient: ingredients
        }
    }

    var isEmpty: Bool { feelings.isEmpty && references.isEmpty && ingredients.isEmpty }

    mutating func update(_ level: TagLevel, _ change: (inout [NamedCount]) -> Void) {
        switch level {
        case .feeling: change(&feelings)
        case .reference: change(&references)
        case .ingredient: change(&ingredients)
        }
    }
}

extension Distillation {
    /// A distillation over the analyzed items of an imported source.
    init(profile: ImportedProfile) {
        let total = max(profile.analyzedItems, 0)

        func counts(_ level: TagLevel) -> [TagCount] {
            var merged: [String: TagCount] = [:]
            var order: [String] = []
            for entry in profile.counts(for: level) {
                let name = TagText.clean(entry.name)
                let key = TagText.key(name)
                guard !key.isEmpty else { continue }
                let count = min(max(entry.count, 1), max(total, 1))
                if let existing = merged[key] {
                    // The same tag twice (different spelling): keep the stronger one.
                    if count > existing.count {
                        merged[key] = TagCount(key: key, name: name, level: level, count: count, total: total)
                    }
                } else {
                    merged[key] = TagCount(key: key, name: name, level: level, count: count, total: total)
                    order.append(key)
                }
            }
            return Self.byCount(order.compactMap { merged[$0] })
        }

        self.init(
            totalItems: total,
            decodedItems: total,
            feelings: counts(.feeling),
            references: counts(.reference),
            ingredients: counts(.ingredient)
        )
    }

    /// Combines two distillations over disjoint sets of items (e.g. an imported board plus saves
    /// added to it later). Counts add up per tag; totals add up.
    func merged(with other: Distillation) -> Distillation {
        if other.totalItems == 0 { return self }
        if totalItems == 0 { return other }
        let total = totalItems + other.totalItems

        func combine(_ level: TagLevel) -> [TagCount] {
            var counts: [String: (name: String, best: Int, count: Int, order: Int)] = [:]
            for (index, tag) in (self.counts(for: level) + other.counts(for: level)).enumerated() {
                if var entry = counts[tag.key] {
                    entry.count += tag.count
                    if tag.count > entry.best {
                        entry.name = tag.name
                        entry.best = tag.count
                    }
                    counts[tag.key] = entry
                } else {
                    counts[tag.key] = (tag.name, tag.count, tag.count, index)
                }
            }
            let ordered = counts.sorted { $0.value.order < $1.value.order }
            let tags: [TagCount] = ordered.map { key, entry in
                TagCount(key: key, name: entry.name, level: level, count: min(entry.count, total), total: total)
            }
            return Self.byCount(tags)
        }

        return Distillation(
            totalItems: total,
            decodedItems: decodedItems + other.decodedItems,
            feelings: combine(.feeling),
            references: combine(.reference),
            ingredients: combine(.ingredient)
        )
    }

    /// Most frequent first; ties keep their incoming order.
    private static func byCount(_ tags: [TagCount]) -> [TagCount] {
        let indexed: [(offset: Int, tag: TagCount)] = tags.enumerated().map { ($0.offset, $0.element) }
        let sorted = indexed.sorted { lhs, rhs in
            if lhs.tag.count != rhs.tag.count { return lhs.tag.count > rhs.tag.count }
            return lhs.offset < rhs.offset
        }
        return sorted.map(\.tag)
    }
}
