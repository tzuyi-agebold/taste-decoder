import Foundation
import Observation

/// The bundled Learn cards (Seed/SeedLearnCards.json), indexed by every title and alias.
/// Generated and edited cards live in SwiftData (LearnCardRecord) and take precedence.
@Observable
final class LearnLibrary {
    private(set) var cards: [LearnCardContent] = []
    private var index: [String: LearnCardContent] = [:]

    init(bundle: Bundle = .main) {
        guard let url = bundle.url(forResource: "SeedLearnCards", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([LearnCardContent].self, from: data)
        else { return }
        cards = decoded.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        for card in decoded {
            for key in card.keys where index[key] == nil { index[key] = card }
        }
    }

    func card(for key: String) -> LearnCardContent? {
        index[key]
    }

    func cards(of kind: LearnKind) -> [LearnCardContent] {
        cards.filter { $0.kind == kind }
    }

    func search(_ query: String) -> [LearnCardContent] {
        let needle = TagText.key(query)
        guard !needle.isEmpty else { return [] }
        return cards.filter { card in
            card.keys.contains { $0.contains(needle) } || TagText.key(card.summary).contains(needle)
        }
    }
}
