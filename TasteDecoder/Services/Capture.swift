import Foundation
import LinkPresentation
import SwiftData
import UIKit

/// Fast capture: save now, interrogate later.
@MainActor
enum Capture {
    @discardableResult
    static func addPhoto(data: Data, to collection: TasteCollection?, context: ModelContext) -> SaveItem? {
        guard let fileName = ImageStore.save(data: data) else { return nil }
        return insert(SaveItem(kind: .photo, imageFileName: fileName), into: collection, context: context)
    }

    @discardableResult
    static func addPhoto(image: UIImage, to collection: TasteCollection?, context: ModelContext) -> SaveItem? {
        guard let fileName = ImageStore.save(image: image) else { return nil }
        return insert(SaveItem(kind: .photo, imageFileName: fileName), into: collection, context: context)
    }

    @discardableResult
    static func addLink(_ url: URL, note: String? = nil, to collection: TasteCollection?, context: ModelContext) -> SaveItem {
        let item = insert(SaveItem(kind: .link, note: note?.nilIfBlank, urlString: url.absoluteString), into: collection, context: context)
        fetchPreview(for: item)
        return item
    }

    @discardableResult
    static func addNote(_ text: String, to collection: TasteCollection?, context: ModelContext) -> SaveItem {
        insert(SaveItem(kind: .note, note: text), into: collection, context: context)
    }

    /// Pasted text: a web link becomes a link save, anything else a note.
    @discardableResult
    static func addPasted(_ text: String, to collection: TasteCollection?, context: ModelContext) -> SaveItem? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = webURL(from: trimmed) { return addLink(url, to: collection, context: context) }
        return addNote(trimmed, to: collection, context: context)
    }

    static func webURL(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(" "), let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), url.host() != nil
        else { return nil }
        return url
    }

    private static func insert(_ item: SaveItem, into collection: TasteCollection?, context: ModelContext) -> SaveItem {
        context.insert(item)
        item.collection = collection
        try? context.save()
        return item
    }

    /// Fetches the page title and preview image so link saves become visual (and taggable by vision).
    static func fetchPreview(for item: SaveItem) {
        guard let url = item.url, item.imageFileName == nil else { return }
        Task { @MainActor in
            let preview = await LinkPreview.fetch(url)
            if item.title == nil, let title = preview.title, !title.isEmpty { item.title = title }
            if item.imageFileName == nil, let data = preview.imageData, let fileName = ImageStore.save(data: data) {
                item.imageFileName = fileName
            }
            try? item.modelContext?.save()
        }
    }
}

enum LinkPreview {
    struct Result {
        var title: String?
        var imageData: Data?
    }

    @MainActor
    static func fetch(_ url: URL) async -> Result {
        let provider = LPMetadataProvider()
        provider.timeout = 12
        guard let metadata = try? await provider.startFetchingMetadata(for: url) else { return Result() }
        var result = Result(title: metadata.title)
        if let imageProvider = metadata.imageProvider ?? metadata.iconProvider {
            result.imageData = await loadImageData(imageProvider)
        }
        return result
    }

    private static func loadImageData(_ provider: NSItemProvider) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                let data = (object as? UIImage)?.jpegData(compressionQuality: 0.9)
                continuation.resume(returning: data)
            }
        }
    }
}

/// Imports saves handed over by the Share Extension, and keeps its collection list current.
@MainActor
enum ShareImporter {
    static func importPending(into context: ModelContext) {
        let pending = SharedInbox.pending()
        guard !pending.isEmpty else { return }
        let collections = (try? context.fetch(FetchDescriptor<TasteCollection>())) ?? []

        for share in pending {
            let collection = share.collectionID.flatMap { id in collections.first { $0.id == id } }
            var created: [SaveItem] = []
            switch share.kind {
            case .image:
                for name in share.imageFileNames where ImageStore.exists(name) {
                    let item = SaveItem(kind: .photo, imageFileName: name, createdAt: share.createdAt)
                    context.insert(item)
                    created.append(item)
                }
            case .link:
                let item = SaveItem(kind: .link, note: share.text?.nilIfBlank, urlString: share.urlString, createdAt: share.createdAt)
                context.insert(item)
                created.append(item)
            case .note:
                let item = SaveItem(kind: .note, note: share.text, createdAt: share.createdAt)
                context.insert(item)
                created.append(item)
            }
            for item in created {
                item.collection = collection
                item.why = share.note?.nilIfBlank
                if item.kind == .link { Capture.fetchPreview(for: item) }
            }
            SharedInbox.remove(share)
        }
        try? context.save()
    }

    static func mirrorCollections(_ collections: [TasteCollection]) {
        SharedInbox.writeCollections(collections.map(\.stub))
    }
}

extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
