import Foundation

/// A save captured by the Share Extension, waiting for the app to import it.
/// The extension never touches the app's database; it drops these small JSON files
/// (plus images) into the App Group and the app picks them up when it becomes active.
struct PendingShare: Codable, Identifiable {
    enum Kind: String, Codable {
        case image
        case link
        case note
    }

    var id = UUID()
    var createdAt = Date()
    var kind: Kind
    var imageFileNames: [String] = []
    var urlString: String?
    var text: String?
    /// "Why did I save this?" — optional, typed in the share sheet.
    var note: String?
    var collectionID: UUID?
}

/// Just enough about a collection for the Share Extension's picker.
struct CollectionStub: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var symbol: String
}

enum SharedInbox {
    private static let collectionsFile = "collections.json"

    static func write(_ share: PendingShare) throws {
        guard let directory = AppGroup.inboxDirectory else { throw CocoaError(.fileNoSuchFile) }
        let data = try JSONEncoder().encode(share)
        try data.write(to: directory.appendingPathComponent("\(share.id.uuidString).json"), options: .atomic)
    }

    static func pending() -> [PendingShare] {
        guard let directory = AppGroup.inboxDirectory,
              let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return [] }
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(PendingShare.self, from: data)
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    static func remove(_ share: PendingShare) {
        guard let directory = AppGroup.inboxDirectory else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(share.id.uuidString).json"))
    }

    // MARK: Collections mirror (app writes, extension reads)

    static func writeCollections(_ stubs: [CollectionStub]) {
        guard let root = AppGroup.sharedContainer, let data = try? JSONEncoder().encode(stubs) else { return }
        try? data.write(to: root.appendingPathComponent(collectionsFile), options: .atomic)
    }

    static func readCollections() -> [CollectionStub] {
        guard let root = AppGroup.sharedContainer,
              let data = try? Data(contentsOf: root.appendingPathComponent(collectionsFile)),
              let stubs = try? JSONDecoder().decode([CollectionStub].self, from: data)
        else { return [] }
        return stubs
    }
}
