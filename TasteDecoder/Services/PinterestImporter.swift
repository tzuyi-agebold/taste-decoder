import Foundation
import Observation
import SwiftData
import UIKit

/// Turns a Pinterest board into one collection: Claude reads a sample of its pins and the
/// collection keeps the summary (no individual saves). Importing the same board again refreshes it.
@MainActor
@Observable
final class PinterestImporter {
    enum Step: Equatable {
        case waiting
        case reading
        case looking(downloaded: Int, of: Int)
        case analyzing(pins: Int, images: Int)
        case done(collectionID: UUID)
        case failed(String)

        var isFinished: Bool {
            switch self {
            case .done, .failed: true
            default: false
            }
        }
    }

    /// Images Claude looks at per board, sampled evenly across it.
    static let sampleSize = 20
    /// Images kept on the device to stand in for the board.
    static let coverCount = 4

    private(set) var steps: [String: Step] = [:]

    var isRunning: Bool { steps.values.contains { !$0.isFinished && $0 != .waiting } }

    /// Imports boards one after another. Failures are reported per board.
    func run(_ boards: [PinterestBoard], context: ModelContext, settings: AppSettings) async {
        for board in boards { steps[board.id] = .waiting }
        for board in boards {
            do {
                let collection = try await importBoard(board, context: context, settings: settings)
                steps[board.id] = .done(collectionID: collection.id)
            } catch {
                steps[board.id] = .failed(error.localizedDescription)
            }
        }
    }

    func reset() { steps = [:] }

    // MARK: - One board

    private func importBoard(_ board: PinterestBoard, context: ModelContext, settings: AppSettings) async throws -> TasteCollection {
        let client = try settings.client()

        steps[board.id] = .reading
        let list = try await PinterestAPI.pins(boardID: board.id)
        let withImages = list.pins.filter { $0.imageURL != nil }
        let sample = Self.evenSample(withImages, count: Self.sampleSize)

        steps[board.id] = .looking(downloaded: 0, of: sample.count)
        var downloaded: [Data] = []
        for chunk in stride(from: 0, to: sample.count, by: 5).map({ Array(sample[$0..<min($0 + 5, sample.count)]) }) {
            downloaded += await Self.download(chunk.compactMap(\.imageURL))
            steps[board.id] = .looking(downloaded: downloaded.count, of: sample.count)
        }

        // Smaller copies for Claude; larger ones kept as the collection's cover.
        let forClaude = downloaded.compactMap { Self.jpeg($0, maxPixel: 768) }
        steps[board.id] = .analyzing(pins: list.pins.count, images: forClaude.count)
        let summary = try await BoardAnalyzer.analyze(
            boardName: board.name,
            boardDescription: board.description,
            totalPins: max(board.pinCount, list.pins.count),
            pinTexts: list.pins.compactMap(\.text),
            images: forClaude,
            vocabulary: Self.vocabulary(context),
            client: client
        )
        let covers = downloaded.prefix(Self.coverCount).compactMap { ImageStore.save(data: $0, maxPixel: 1200) }

        return try save(board, summary: summary, covers: covers, context: context)
    }

    private func save(_ board: PinterestBoard, summary: BoardSummary, covers: [String], context: ModelContext) throws -> TasteCollection {
        let source = CollectionSource.pinterest.rawValue
        let boardID = board.id
        let existing = try context.fetch(FetchDescriptor<TasteCollection>(
            predicate: #Predicate { $0.sourceRaw == source && $0.sourceID == boardID }
        )).first

        let collection: TasteCollection
        if let existing {
            collection = existing
            // Keep what the user chose (name, icon, wording); refresh what came from the board.
            existing.coverImageNames.forEach(ImageStore.delete(named:))
        } else {
            let all = try context.fetch(FetchDescriptor<TasteCollection>())
            collection = TasteCollection(name: board.name, domain: summary.domain, verb: summary.verb, symbol: summary.symbol,
                                         sortIndex: (all.map(\.sortIndex).max() ?? -1) + 1)
            context.insert(collection)
        }

        collection.sourceRaw = source
        collection.sourceID = board.id
        collection.sourceURL = board.url
        collection.sourceItemCount = board.pinCount
        collection.importedAt = Date()
        collection.summary = summary.about
        collection.importedProfile = summary.profile
        collection.coverImageNames = covers
        collection.statement = summary.statement
        collection.statementSignature = collection.effectiveDistillation(items: collection.items).signature
        try context.save()
        return collection
    }

    // MARK: - Helpers

    /// Up to `count` items spread evenly from first to last.
    static func evenSample<T>(_ items: [T], count: Int) -> [T] {
        guard items.count > count, count > 0 else { return items }
        let step = Double(items.count) / Double(count)
        return (0..<count).map { items[Int(Double($0) * step)] }
    }

    private static func download(_ urls: [String]) async -> [Data] {
        await withTaskGroup(of: (Int, Data?).self) { group in
            for (index, string) in urls.enumerated() {
                group.addTask {
                    guard let url = URL(string: string), url.scheme == "https" else { return (index, nil) }
                    var request = URLRequest(url: url, timeoutInterval: 20)
                    request.setValue("image/*", forHTTPHeaderField: "accept")
                    guard let (data, response) = try? await URLSession.shared.data(for: request),
                          (response as? HTTPURLResponse)?.statusCode == 200 else { return (index, nil) }
                    return (index, data)
                }
            }
            var results: [(Int, Data)] = []
            for await (index, data) in group { if let data { results.append((index, data)) } }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    private static func jpeg(_ data: Data, maxPixel: CGFloat) -> Data? {
        guard let image = ImageStore.downsample(data: data, maxPixel: maxPixel) else { return nil }
        return UIImage(cgImage: image).jpegData(compressionQuality: 0.8)
    }

    /// The user's most-used confirmed tags per level, so Claude's wording lines up with theirs.
    private static func vocabulary(_ context: ModelContext) -> [TagLevel: [String]] {
        let tags = (try? context.fetch(FetchDescriptor<TagEntry>(predicate: #Predicate { $0.statusRaw == "confirmed" }))) ?? []
        var result: [TagLevel: [String]] = [:]
        for level in TagLevel.allCases {
            var counts: [String: (name: String, count: Int)] = [:]
            for tag in tags where tag.level == level {
                counts[tag.key, default: (tag.name, 0)].count += 1
            }
            result[level] = counts.values.sorted { $0.count > $1.count }.prefix(20).map(\.name)
        }
        return result
    }
}
