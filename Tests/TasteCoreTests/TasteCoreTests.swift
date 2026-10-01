import XCTest
#if canImport(TasteCore)
@testable import TasteCore
#else
@testable import TasteDecoder
#endif

final class TagTextTests: XCTestCase {
    func testKeyIgnoresCaseSpacingAndPunctuation() {
        XCTAssertEqual(TagText.key("  Harsh   Flash Lighting. "), "harsh flash lighting")
        XCTAssertEqual(TagText.key("harsh flash lighting"), "harsh flash lighting")
    }

    func testKeyUnifiesDashesAndDiacritics() {
        XCTAssertEqual(TagText.key("90–100 BPM"), TagText.key("90-100 bpm"))
        XCTAssertEqual(TagText.key("Rosé"), "rose")
    }

    func testCleanKeepsCasingButTidies() {
        XCTAssertEqual(TagText.clean("  David   Lynch, "), "David Lynch")
    }
}

final class DistillerTests: XCTestCase {
    private func item(_ feelings: [String] = [], _ references: [String] = [], _ ingredients: [String] = []) -> ItemSnapshot {
        ItemSnapshot(
            id: UUID(),
            tags: feelings.map { TagSnapshot(name: $0, level: .feeling) }
                + references.map { TagSnapshot(name: $0, level: .reference) }
                + ingredients.map { TagSnapshot(name: $0, level: .ingredient) }
        )
    }

    /// The "Uncomfy" example: ten decoded saves.
    private var uncomfy: [ItemSnapshot] {
        [
            item(["uncomfortable", "uneasy"], ["David Lynch"], ["distorted proportions", "harsh flash lighting", "acidic color"]),
            item(["electric", "uncomfortable"], ["90s rave flyer"], ["harsh flash lighting", "fisheye lens", "distorted proportions"]),
            item(["uncomfortable", "off-kilter"], ["Juergen Teller"], ["acidic color", "harsh flash lighting", "film grain"]),
            item(["uneasy"], ["Francis Bacon"], ["distorted proportions", "hand-drawn mixed media", "acidic color"]),
            item(["uncomfortable", "electric"], ["Juergen Teller"], ["harsh flash lighting", "film grain", "direct eye contact"]),
            item(["off-kilter", "uncomfortable"], ["David Lynch"], ["distorted proportions", "harsh flash lighting", "acidic color"]),
            item(["late-night", "uneasy"], ["David Lynch"], ["acidic color", "harsh flash lighting", "film grain"]),
            item(["uncomfortable"], [], ["distorted proportions", "acidic color", "harsh flash lighting"]),
            item(["electric", "late-night"], ["90s rave flyer"], ["harsh flash lighting", "motion blur", "distorted proportions"]),
            item(["uncomfortable", "uneasy"], ["David Lynch"], ["harsh flash lighting", "distorted proportions", "film grain"]),
        ]
    }

    func testCountsDistinctSavesPerIngredient() {
        let d = Distiller.distill(uncomfy)
        XCTAssertEqual(d.totalItems, 10)
        XCTAssertEqual(d.decodedItems, 10)
        let counts = Dictionary(uniqueKeysWithValues: d.ingredients.map { ($0.key, $0.count) })
        XCTAssertEqual(counts["harsh flash lighting"], 9)
        XCTAssertEqual(counts["distorted proportions"], 7)
        XCTAssertEqual(counts["acidic color"], 6)
        XCTAssertEqual(counts["film grain"], 4)
        XCTAssertEqual(d.ingredients.first?.ratioText, "9 of 10")
    }

    func testSignatureIngredientsAreRecurringAndCapped() {
        let d = Distiller.distill(uncomfy)
        XCTAssertEqual(d.signatureIngredients.map(\.name),
                       ["harsh flash lighting", "distorted proportions", "acidic color", "film grain"])
        XCTAssertFalse(d.isTentative)
        XCTAssertEqual(d.leadFeeling?.name, "uncomfortable")
        XCTAssertEqual(d.leadReference?.name, "David Lynch")
    }

    func testDuplicateTagOnOneItemCountsOnce() {
        let d = Distiller.distill([item([], [], ["Film grain", "film grain "]), item([], [], ["film grain"])])
        XCTAssertEqual(d.ingredients.count, 1)
        XCTAssertEqual(d.ingredients.first?.count, 2)
        XCTAssertEqual(d.ingredients.first?.name, "film grain")
    }

    func testUndecodedSavesStillCountInTotal() {
        let d = Distiller.distill([item(["cozy"], [], ["walnut wood"]), item(["cozy"], [], ["walnut wood"]), item()])
        XCTAssertEqual(d.totalItems, 3)
        XCTAssertEqual(d.decodedItems, 2)
        XCTAssertEqual(d.ingredients.first?.ratioText, "2 of 3")
    }

    func testTemplateStatementFollowsFeelingPlusIngredients() {
        let d = Distiller.distill(uncomfy)
        XCTAssertEqual(
            TasteStatement.template(domain: "visuals", distillation: d),
            "I like visuals that feel uncomfortable — harsh flash lighting, distorted proportions, acidic color, film grain."
        )
        XCTAssertEqual(TasteStatement.headline(d), "9 of 10 saves share harsh flash lighting.")
    }

    func testTemplateUsesVerbAndHandlesMissingFeeling() {
        let wines = [item(["warm"], [], ["caramel", "toasted oak"]), item(["warm"], [], ["caramel", "toasted oak", "leather"])]
        XCTAssertEqual(TasteStatement.template(domain: "reds", verb: "taste", distillation: Distiller.distill(wines)),
                       "I like reds that taste warm — caramel, toasted oak.")
        let noFeeling = [item([], [], ["walnut wood"]), item([], [], ["walnut wood"])]
        XCTAssertEqual(TasteStatement.template(domain: "rooms", distillation: Distiller.distill(noFeeling)),
                       "I like rooms with walnut wood.")
        XCTAssertNil(TasteStatement.template(domain: "rooms", distillation: Distiller.distill([item()])))
    }

    func testSignatureChangesWhenTheRecipeChanges() {
        let before = Distiller.distill(uncomfy)
        var edited = uncomfy
        edited[0] = item(["uncomfortable"], ["David Lynch"], ["chrome type"])
        edited[1] = item(["uncomfortable"], [], ["chrome type"])
        let after = Distiller.distill(edited)
        XCTAssertNotEqual(before.signature, after.signature)
        XCTAssertEqual(before.signature, Distiller.distill(uncomfy).signature)
    }
}

final class ComparerTests: XCTestCase {
    private func distill(_ items: [[(String, TagLevel)]]) -> Distillation {
        Distiller.distill(items.map { tags in
            ItemSnapshot(id: UUID(), tags: tags.map { TagSnapshot(name: $0.0, level: $0.1) })
        })
    }

    func testFindsCommonGroundAcrossLevels() {
        let wine = distill([
            [("warm", .feeling), ("cozy", .feeling), ("leather", .ingredient), ("caramel", .ingredient)],
            [("warm", .feeling), ("leather", .ingredient), ("toasted oak", .ingredient)],
        ])
        let rooms = distill([
            [("cozy", .feeling), ("warm", .feeling), ("walnut wood", .ingredient), ("leather", .ingredient)],
            [("cozy", .feeling), ("late-night", .reference), ("walnut wood", .ingredient)],
        ])
        let comparison = Comparer.compare(wine, rooms)
        XCTAssertEqual(Set(comparison.common.map(\.key)), ["warm", "cozy", "leather"])
        XCTAssertEqual(Set(comparison.onlyA.map(\.key)), ["caramel", "toasted oak"])
        XCTAssertEqual(Set(comparison.onlyB.map(\.key)), ["walnut wood", "late-night"])
        XCTAssertEqual(comparison.overlap, 3.0 / 7.0, accuracy: 0.0001)
        XCTAssertEqual(comparison.sentence(nameA: "Reds", nameB: "Rooms"),
                       "Reds and Rooms both feel warm and cozy — because of leather.")
    }

    func testNoCommonGroundStillProducesASentence() {
        let a = distill([[("acidic color", .ingredient)]])
        let b = distill([[("walnut wood", .ingredient)]])
        let comparison = Comparer.compare(a, b)
        XCTAssertTrue(comparison.common.isEmpty)
        XCTAssertTrue(comparison.sentence(nameA: "A", nameB: "B").hasPrefix("No common ground yet"))
    }
}

final class PantryTests: XCTestCase {
    func testBuildsGlossaryWithCountsAndCollections() {
        let a = UUID(), b = UUID(), c = UUID()
        let entries = PantryIndex.build([
            TagUsage(name: "flash lighting", level: .ingredient, itemID: a, collectionName: "Uncomfy"),
            TagUsage(name: "Flash lighting", level: .ingredient, itemID: b, collectionName: "Uncomfy"),
            TagUsage(name: "flash lighting", level: .ingredient, itemID: c, collectionName: "2am Songs"),
            TagUsage(name: "cozy", level: .feeling, itemID: c, collectionName: nil),
        ])
        XCTAssertEqual(entries.first?.name, "flash lighting")
        XCTAssertEqual(entries.first?.itemCount, 3)
        XCTAssertEqual(entries.first?.collectionNames, ["Uncomfy", "2am Songs"])
        XCTAssertEqual(entries.last?.collections, [PantryIndex.unsortedName: 1])
    }

    func testWhyItMattersNamesTheCollection() {
        let ids = (0..<6).map { _ in UUID() }
        let entries = PantryIndex.build(ids.map {
            TagUsage(name: "flash lighting", level: .ingredient, itemID: $0, collectionName: "Uncomfy")
        })
        let line = PantryIndex.whyItMattersToYou(keys: ["flash lighting"], title: "flash lighting",
                                                 entries: entries, collectionSizes: ["Uncomfy": 10])
        XCTAssertEqual(line, "You have 6 saves tagged “flash lighting” — 6 of 10 in Uncomfy. This is a core ingredient of your taste.")
        let missing = PantryIndex.whyItMattersToYou(keys: ["ring flash"], title: "ring flash", entries: entries, collectionSizes: [:])
        XCTAssertTrue(missing.hasPrefix("It isn't in your saves yet"))
    }
}

final class LearnCardDecodingTests: XCTestCase {
    func testDecodesMinimalCard() throws {
        let json = #"{"title": "Risograph", "kind": "term", "summary": "A stencil printer."}"#
        let card = try JSONDecoder().decode(LearnCardContent.self, from: Data(json.utf8))
        XCTAssertEqual(card.kind, .term)
        XCTAssertTrue(card.examples.isEmpty)
        XCTAssertEqual(card.keys, ["risograph"])
    }
}
