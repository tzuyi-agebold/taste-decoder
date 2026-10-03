import XCTest
#if canImport(TasteCore)
@testable import TasteCore
#else
@testable import TasteDecoder
#endif

final class ImportedProfileTests: XCTestCase {
    private let board = ImportedProfile(
        analyzedItems: 20,
        totalItems: 143,
        feelings: [NamedCount(name: "uncomfortable", count: 14), NamedCount(name: "electric", count: 6)],
        references: [NamedCount(name: "Juergen Teller", count: 5)],
        ingredients: [
            NamedCount(name: "acidic color", count: 9),
            NamedCount(name: "harsh flash lighting", count: 12),
            NamedCount(name: "Harsh  flash lighting.", count: 3),
            NamedCount(name: "film grain", count: 40),
            NamedCount(name: "  ", count: 4),
        ]
    )

    func testProfileBecomesADistillationOverAnalyzedItems() {
        let distillation = Distillation(profile: board)
        XCTAssertEqual(distillation.totalItems, 20)
        XCTAssertEqual(distillation.decodedItems, 20)
        XCTAssertEqual(distillation.leadFeeling?.name, "uncomfortable")
        // Duplicates collapse (keeping the stronger count), blanks drop, counts clamp to the total, sorted by count.
        XCTAssertEqual(distillation.ingredients.map(\.name), ["film grain", "harsh flash lighting", "acidic color"])
        XCTAssertEqual(distillation.ingredients.map(\.count), [20, 12, 9])
        XCTAssertEqual(distillation.ingredients.first?.ratioText, "20 of 20")
        XCTAssertEqual(distillation.ingredients[1].key, TagText.key("harsh flash lighting"))
    }

    func testProfileStatementTemplate() {
        let distillation = Distillation(profile: board)
        XCTAssertEqual(
            TasteStatement.template(domain: "visuals", distillation: distillation),
            "I like visuals that feel uncomfortable — film grain, harsh flash lighting, acidic color."
        )
    }

    func testMergingWithEmptyKeepsTheOtherSide() {
        let profile = Distillation(profile: board)
        XCTAssertEqual(Distillation.empty.merged(with: profile).signature, profile.signature)
        XCTAssertEqual(profile.merged(with: .empty).totalItems, 20)
    }

    func testMergeAddsCountsAndTotals() {
        let saves = Distiller.distill([
            ItemSnapshot(id: UUID(), tags: [TagSnapshot(name: "Acidic Color", level: .ingredient), TagSnapshot(name: "cozy", level: .feeling)]),
            ItemSnapshot(id: UUID(), tags: [TagSnapshot(name: "acidic color", level: .ingredient)]),
            ItemSnapshot(id: UUID(), tags: []),
        ])
        let merged = Distillation(profile: board).merged(with: saves)
        XCTAssertEqual(merged.totalItems, 23)
        XCTAssertEqual(merged.decodedItems, 22)
        let acidic = merged.ingredients.first { $0.key == TagText.key("acidic color") }
        XCTAssertEqual(acidic?.count, 11)
        XCTAssertEqual(acidic?.total, 23)
        XCTAssertEqual(acidic?.name, "acidic color")
        XCTAssertTrue(merged.feelings.contains { $0.name == "cozy" && $0.count == 1 })
    }

    func testImportedCollectionsCompareWithSaves() {
        let saves = Distiller.distill([
            ItemSnapshot(id: UUID(), tags: [TagSnapshot(name: "harsh flash lighting", level: .ingredient)]),
        ])
        let comparison = Comparer.compare(Distillation(profile: board), saves)
        XCTAssertEqual(comparison.common.map(\.name), ["harsh flash lighting"])
    }

    func testProfileRoundTripsThroughJSON() throws {
        let data = try JSONEncoder().encode(board)
        XCTAssertEqual(try JSONDecoder().decode(ImportedProfile.self, from: data), board)
    }
}

final class SyncFingerprintTests: XCTestCase {
    func testStableAndSensitive() {
        let a = SyncFingerprint.hash(["Uncomfy", "visuals", nil])
        XCTAssertEqual(a, SyncFingerprint.hash(["Uncomfy", "visuals", nil]))
        XCTAssertNotEqual(a, SyncFingerprint.hash(["Uncomfy", "visuals", ""]))
        XCTAssertNotEqual(SyncFingerprint.hash(["a", nil]), SyncFingerprint.hash([nil, "a"]))
        XCTAssertNotEqual(SyncFingerprint.hash(["ab", "c"]), SyncFingerprint.hash(["a", "bc"]))
        // Known value guards against accidental algorithm changes (which would re-upload everything).
        XCTAssertEqual(SyncFingerprint.hash([]), "cbf29ce484222325")
    }

    func testDatesRoundToMilliseconds() {
        let date = Date(timeIntervalSince1970: 1_790_000_000.123_4)
        XCTAssertEqual(SyncFingerprint.field(date), "1790000000123")
        XCTAssertEqual(SyncFingerprint.field(date), SyncFingerprint.field(Date(timeIntervalSince1970: 1_790_000_000.1231)))
    }
}
