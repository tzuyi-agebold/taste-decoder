import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Share Extension entry point: save from any app while scrolling, interrogate later in Taste Decoder.
final class ShareViewController: UIViewController {
    private let model = ShareModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark

        model.onFinish = { [weak self] saved in
            guard let context = self?.extensionContext else { return }
            if saved {
                context.completeRequest(returningItems: nil)
            } else {
                context.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
            }
        }

        let host = UIHostingController(rootView: ShareComposerView(model: model))
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.backgroundColor = .clear
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        host.didMove(toParent: self)

        let context = extensionContext
        Task { @MainActor in await model.load(from: context) }
    }
}

@Observable
final class ShareModel {
    var isLoading = true
    var isSaving = false
    var groupUnavailable = false
    var errorMessage: String?

    var imageData: [Data] = []
    var thumbnails: [UIImage] = []
    var url: URL?
    var pageTitle: String?
    var text: String?

    var note = ""
    var collectionID: UUID?
    var collections: [CollectionStub] = []

    var onFinish: (Bool) -> Void = { _ in }

    var hasContent: Bool { !imageData.isEmpty || url != nil || !(text ?? "").isEmpty }

    @MainActor
    func load(from context: NSExtensionContext?) async {
        defer { isLoading = false }
        guard AppGroup.isAvailable else {
            groupUnavailable = true
            return
        }
        collections = SharedInbox.readCollections()

        let items = (context?.inputItems as? [NSExtensionItem]) ?? []
        for item in items {
            if let title = item.attributedContentText?.string, !title.isEmpty { pageTitle = title }
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    if let data = await Self.loadImageData(provider) { imageData.append(data) }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let loaded = await Self.loadURL(provider), !loaded.isFileURL { url = loaded }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    if let loaded = await Self.loadText(provider) { text = loaded }
                }
            }
        }

        // Plain text that is really a link becomes a link save.
        if url == nil, let candidate = text?.trimmingCharacters(in: .whitespacesAndNewlines),
           let parsed = URL(string: candidate), let scheme = parsed.scheme?.lowercased(), ["http", "https"].contains(scheme) {
            url = parsed
            text = nil
        }

        thumbnails = imageData.prefix(3).compactMap { data in
            ImageStore.downsample(data: data, maxPixel: 400).map { UIImage(cgImage: $0) }
        }
    }

    @MainActor
    func save() {
        guard hasContent, !isSaving else { return }
        isSaving = true
        var share: PendingShare
        if !imageData.isEmpty {
            let names = imageData.compactMap { ImageStore.save(data: $0) }
            guard !names.isEmpty else {
                errorMessage = "Couldn't save the image."
                isSaving = false
                return
            }
            share = PendingShare(kind: .image, imageFileNames: names)
        } else if let url {
            share = PendingShare(kind: .link, urlString: url.absoluteString, text: text ?? pageTitle)
        } else {
            share = PendingShare(kind: .note, text: text)
        }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        share.note = trimmedNote.isEmpty ? nil : trimmedNote
        share.collectionID = collectionID

        do {
            try SharedInbox.write(share)
            onFinish(true)
        } catch {
            errorMessage = "Couldn't hand this to Taste Decoder. Open the app and try again."
            isSaving = false
        }
    }

    func cancel() {
        onFinish(false)
    }

    // MARK: Loading attachments

    private static func loadImageData(_ provider: NSItemProvider) async -> Data? {
        let data: Data? = await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
        if let data { return data }
        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { item, _ in
                switch item {
                case let url as URL: continuation.resume(returning: try? Data(contentsOf: url))
                case let image as UIImage: continuation.resume(returning: image.jpegData(compressionQuality: 0.9))
                case let data as Data: continuation.resume(returning: data)
                default: continuation.resume(returning: nil)
                }
            }
        }
    }

    private static func loadURL(_ provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url)
            }
        }
    }

    private static func loadText(_ provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: String.self) { text, _ in
                continuation.resume(returning: text)
            }
        }
    }
}
