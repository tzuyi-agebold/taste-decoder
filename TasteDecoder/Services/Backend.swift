import Foundation
import Supabase

// The Taste Decoder backend (Supabase): Google sign-in, the synced copy of your data,
// the Claude proxy and Pinterest. Everything here is optional — with no project configured
// the app runs local-only exactly as before.
//
// This file only uses Foundation and Supabase so it stays independent of SwiftData and UIKit.

enum Backend {
    /// Configured from Info.plist (`SupabaseProjectRef`, `SupabaseAnonKey`, set in Config/Secrets.xcconfig).
    static let client: SupabaseClient? = { () -> SupabaseClient? in
        guard let url = projectURL, let key = info("SupabaseAnonKey") else { return nil }
        return SupabaseClient(
            supabaseURL: url,
            supabaseKey: key,
            options: SupabaseClientOptions(auth: .init(emitLocalSessionAsInitialSession: true))
        )
    }()

    static var isConfigured: Bool { client != nil }

    static var projectURL: URL? {
        guard let ref = info("SupabaseProjectRef") else { return nil }
        // A full URL also works, e.g. for a self-hosted or local project.
        if ref.contains(".") || ref.contains(":") { return URL(string: ref.hasPrefix("http") ? ref : "https://\(ref)") }
        return URL(string: "https://\(ref).supabase.co")
    }

    static var anonKey: String? { info("SupabaseAnonKey") }

    /// The iOS OAuth client id for Google Sign-In.
    static var googleClientID: String? { info("GIDClientID") }

    static var currentUserID: UUID? {
        guard let session = client?.auth.currentSession, !session.isExpired || !session.refreshToken.isEmpty else { return nil }
        return session.user.id
    }

    static var isSignedIn: Bool { currentUserID != nil }

    /// A fresh access token (refreshed if needed).
    static func accessToken() async throws -> String {
        guard let client else { throw BackendError.notConfigured }
        return try await client.auth.session.accessToken
    }

    static var claudeProxyURL: URL? {
        projectURL?.appendingPathComponent("functions/v1/claude")
    }

    private static func info(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else { return nil }
        return trimmed
    }
}

enum BackendError: LocalizedError {
    case notConfigured
    case signedOut
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "The Taste Decoder backend isn't set up in this build. See the README."
        case .signedOut: "Sign in with Google in Settings first."
        case let .server(message): message
        }
    }

    /// Turns Edge Function failures into the message the function sent.
    static func wrap(_ error: Error) -> Error {
        if case let FunctionsError.httpError(code, data) = error {
            struct Envelope: Decodable {
                struct Detail: Decodable { let message: String }
                let error: Detail
            }
            if let message = try? JSONDecoder().decode(Envelope.self, from: data).error.message {
                return BackendError.server(message)
            }
            return BackendError.server("The server returned an error (\(code)).")
        }
        return error
    }
}

// MARK: - Synced rows

/// Tables mirrored from the local SwiftData store.
enum SyncTable: String, CaseIterable, Sendable {
    case collections, saves, tags, learnCards = "learn_cards"

    /// Primary key column alongside user_id.
    var keyColumn: String { self == .learnCards ? "key" : "id" }
}

protocol SyncRow: Codable, Sendable {
    static var table: SyncTable { get }
    /// The row's id (or key, for learn cards) as a string.
    var rowID: String { get }
    var deletedAt: Date? { get }
    /// Content hash of everything the app stores; equal hashes mean nothing to sync.
    var fingerprint: String { get }
}

struct CollectionRow: SyncRow, Equatable {
    static let table = SyncTable.collections

    var id: UUID
    var userID: UUID?
    var name: String
    var domain: String
    var verb: String
    var symbol: String
    var sortIndex: Int
    var statement: String?
    var statementSignature: String?
    var source: String?
    var sourceID: String?
    var sourceURL: String?
    var sourceItemCount: Int
    var importedAt: Date?
    var summary: String?
    var profile: ImportedProfile?
    var coverImages: [String]
    var createdAt: Date
    var deletedAt: Date?

    var rowID: String { id.uuidString }

    var fingerprint: String {
        let profileJSON = profile.flatMap { try? SyncJSON.encoder.encode($0) }.map { String(decoding: $0, as: UTF8.self) }
        return SyncFingerprint.hash([
            name, domain, verb, symbol, SyncFingerprint.field(sortIndex), statement, statementSignature,
            source, sourceID, sourceURL, SyncFingerprint.field(sourceItemCount), SyncFingerprint.field(importedAt),
            summary, profileJSON, coverImages.joined(separator: "\n"), SyncFingerprint.field(createdAt),
        ])
    }

    enum CodingKeys: String, CodingKey {
        case id, name, domain, verb, symbol, statement, source, summary, profile
        case userID = "user_id", sortIndex = "sort_index", statementSignature = "statement_signature"
        case sourceID = "source_id", sourceURL = "source_url", sourceItemCount = "source_item_count"
        case importedAt = "imported_at", coverImages = "cover_images", createdAt = "created_at", deletedAt = "deleted_at"
    }

    // Explicit nulls on encode, so clearing a field (or un-deleting) reaches the server.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(userID, forKey: .userID)
        try c.encode(name, forKey: .name)
        try c.encode(domain, forKey: .domain)
        try c.encode(verb, forKey: .verb)
        try c.encode(symbol, forKey: .symbol)
        try c.encode(sortIndex, forKey: .sortIndex)
        try c.encode(statement, forKey: .statement)
        try c.encode(statementSignature, forKey: .statementSignature)
        try c.encode(source, forKey: .source)
        try c.encode(sourceID, forKey: .sourceID)
        try c.encode(sourceURL, forKey: .sourceURL)
        try c.encode(sourceItemCount, forKey: .sourceItemCount)
        try c.encode(importedAt, forKey: .importedAt)
        try c.encode(summary, forKey: .summary)
        try c.encode(profile, forKey: .profile)
        try c.encode(coverImages, forKey: .coverImages)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(deletedAt, forKey: .deletedAt)
    }
}

struct SaveRow: SyncRow, Equatable {
    static let table = SyncTable.saves

    var id: UUID
    var userID: UUID?
    var collectionID: UUID?
    var kind: String
    var title: String?
    var note: String?
    var url: String?
    var imageName: String?
    var artStyle: String?
    var artSeed: Int
    var why: String?
    var decodedAt: Date?
    var createdAt: Date
    var deletedAt: Date?

    var rowID: String { id.uuidString }

    var fingerprint: String {
        SyncFingerprint.hash([
            collectionID?.uuidString, kind, title, note, url, imageName, artStyle, SyncFingerprint.field(artSeed),
            why, SyncFingerprint.field(decodedAt), SyncFingerprint.field(createdAt),
        ])
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, title, note, url, why
        case userID = "user_id", collectionID = "collection_id", imageName = "image_name", artStyle = "art_style"
        case artSeed = "art_seed", decodedAt = "decoded_at", createdAt = "created_at", deletedAt = "deleted_at"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(userID, forKey: .userID)
        try c.encode(collectionID, forKey: .collectionID)
        try c.encode(kind, forKey: .kind)
        try c.encode(title, forKey: .title)
        try c.encode(note, forKey: .note)
        try c.encode(url, forKey: .url)
        try c.encode(imageName, forKey: .imageName)
        try c.encode(artStyle, forKey: .artStyle)
        try c.encode(artSeed, forKey: .artSeed)
        try c.encode(why, forKey: .why)
        try c.encode(decodedAt, forKey: .decodedAt)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(deletedAt, forKey: .deletedAt)
    }
}

struct TagRow: SyncRow, Equatable {
    static let table = SyncTable.tags

    var id: UUID
    var userID: UUID?
    var saveID: UUID?
    var name: String
    var key: String
    var level: String
    var status: String
    var source: String
    var createdAt: Date
    var deletedAt: Date?

    var rowID: String { id.uuidString }

    var fingerprint: String {
        SyncFingerprint.hash([saveID?.uuidString, name, key, level, status, source, SyncFingerprint.field(createdAt)])
    }

    enum CodingKeys: String, CodingKey {
        case id, name, key, level, status, source
        case userID = "user_id", saveID = "save_id", createdAt = "created_at", deletedAt = "deleted_at"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(userID, forKey: .userID)
        try c.encode(saveID, forKey: .saveID)
        try c.encode(name, forKey: .name)
        try c.encode(key, forKey: .key)
        try c.encode(level, forKey: .level)
        try c.encode(status, forKey: .status)
        try c.encode(source, forKey: .source)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(deletedAt, forKey: .deletedAt)
    }
}

struct LearnCardRow: SyncRow, Equatable {
    static let table = SyncTable.learnCards

    var key: String
    var userID: UUID?
    var payload: LearnCardContent
    var origin: String
    var deletedAt: Date?

    var rowID: String { key }

    var fingerprint: String {
        let json = (try? SyncJSON.encoder.encode(payload)).map { String(decoding: $0, as: UTF8.self) }
        return SyncFingerprint.hash([key, json, origin])
    }

    enum CodingKeys: String, CodingKey {
        case key, payload, origin
        case userID = "user_id", deletedAt = "deleted_at"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(key, forKey: .key)
        try c.encode(userID, forKey: .userID)
        try c.encode(payload, forKey: .payload)
        try c.encode(origin, forKey: .origin)
        try c.encode(deletedAt, forKey: .deletedAt)
    }
}

enum SyncJSON {
    /// Sorted keys so the same value always hashes the same.
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}

/// A row as last seen on the server, with its server timestamp (the pull cursor).
struct Pulled<Row: SyncRow>: Decodable, Sendable {
    let row: Row
    let updatedAt: Date

    private enum CodingKeys: String, CodingKey { case updatedAt = "updated_at" }

    init(from decoder: Decoder) throws {
        row = try Row(from: decoder)
        updatedAt = try decoder.container(keyedBy: CodingKeys.self).decode(Date.self, forKey: .updatedAt)
    }
}

// MARK: - Remote store

/// Reads and writes the signed-in user's rows and images.
struct RemoteStore: Sendable {
    let client: SupabaseClient
    let userID: UUID

    static let imagesBucket = "images"
    private static let pageSize = 500

    init(client: SupabaseClient, userID: UUID) {
        self.client = client
        self.userID = userID
    }

    /// The store for whoever is signed in, or nil.
    static func current() -> RemoteStore? {
        guard let client = Backend.client, let userID = Backend.currentUserID else { return nil }
        return RemoteStore(client: client, userID: userID)
    }

    /// Rows changed after `since` (all rows when nil), oldest first, including soft-deleted ones.
    func changes<Row: SyncRow>(_ type: Row.Type, since: Date?) async throws -> [Pulled<Row>] {
        var all: [Pulled<Row>] = []
        var offset = 0
        while true {
            var query = client.from(Row.table.rawValue).select().eq("user_id", value: userID.uuidString)
            if let since { query = query.gt("updated_at", value: since) }
            let page: [Pulled<Row>] = try await query
                .order("updated_at", ascending: true)
                .order(Row.table.keyColumn, ascending: true)
                .range(from: offset, to: offset + Self.pageSize - 1)
                .execute()
                .value
            all += page
            if page.count < Self.pageSize { return all }
            offset += page.count
        }
    }

    func upsert<Row: SyncRow>(_ rows: [Row]) async throws {
        guard !rows.isEmpty else { return }
        for start in stride(from: 0, to: rows.count, by: 200) {
            let chunk = Array(rows[start..<min(start + 200, rows.count)])
            try await client.from(Row.table.rawValue)
                .upsert(chunk, onConflict: "user_id,\(Row.table.keyColumn)", returning: .minimal)
                .execute()
        }
    }

    /// Soft-deletes rows so other devices learn about it.
    func markDeleted(_ table: SyncTable, ids: [String]) async throws {
        guard !ids.isEmpty else { return }
        struct Tombstone: Encodable { let deleted_at: Date }
        for start in stride(from: 0, to: ids.count, by: 200) {
            let chunk = Array(ids[start..<min(start + 200, ids.count)])
            try await client.from(table.rawValue)
                .update(Tombstone(deleted_at: Date()), returning: .minimal)
                .eq("user_id", value: userID.uuidString)
                .in(table.keyColumn, values: chunk)
                .execute()
        }
    }

    // MARK: Images

    private func imagePath(_ name: String) -> String { "\(userID.uuidString.lowercased())/\(name)" }

    func uploadImage(named name: String, data: Data) async throws {
        try await client.storage.from(Self.imagesBucket).upload(
            imagePath(name), data: data, options: FileOptions(contentType: "image/jpeg", upsert: true)
        )
    }

    func downloadImage(named name: String) async throws -> Data {
        try await client.storage.from(Self.imagesBucket).download(path: imagePath(name))
    }

    // MARK: Profile

    struct Profile: Decodable, Sendable {
        let displayName: String?
        let avatarURL: String?

        enum CodingKeys: String, CodingKey {
            case displayName = "display_name", avatarURL = "avatar_url"
        }
    }

    func profile() async throws -> Profile? {
        let rows: [Profile] = try await client.from("profiles").select("display_name, avatar_url")
            .eq("id", value: userID.uuidString).limit(1).execute().value
        return rows.first
    }
}
