import Foundation

/// Locations shared by the app and the Share Extension.
///
/// With an App Group, images and pending shares live in the group container so the
/// extension can hand saves to the app. Without one (free Apple ID), the app falls back
/// to its own Application Support folder and the extension explains why it can't save.
enum AppGroup {
    static var identifier: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else { return nil }
        return trimmed
    }

    static var sharedContainer: URL? {
        guard let identifier else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    static var isAvailable: Bool { sharedContainer != nil }

    /// Root for files both targets read: the group container, or Application Support as a fallback.
    static var rootDirectory: URL {
        if let sharedContainer { return sharedContainer }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return ensure(support.appendingPathComponent("TasteDecoder", isDirectory: true))
    }

    static var imagesDirectory: URL {
        ensure(rootDirectory.appendingPathComponent("Images", isDirectory: true))
    }

    /// Pending saves written by the Share Extension. Nil without an App Group.
    static var inboxDirectory: URL? {
        guard let sharedContainer else { return nil }
        return ensure(sharedContainer.appendingPathComponent("Inbox", isDirectory: true))
    }

    @discardableResult
    private static func ensure(_ url: URL) -> URL {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
