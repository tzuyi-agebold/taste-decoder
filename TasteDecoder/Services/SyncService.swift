import Foundation
import Observation
import SwiftData

/// Keeps the local SwiftData store and the signed-in user's cloud copy in step.
///
/// The app stays local-first: every screen reads and writes SwiftData as before. Sync compares
/// each row's content fingerprint with the one recorded at the last sync (`SyncRecord`), so no
/// mutation site needs to know about it:
/// - pull: rows the server changed since the cursor are applied unless the local row has unsynced edits;
/// - push: rows whose fingerprint changed are upserted; rows that disappeared are soft-deleted;
/// - images: referenced files missing on either side are uploaded or downloaded.
@MainActor
@Observable
final class SyncService {
    enum Phase: Equatable {
        case idle
        case syncing
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var lastSyncedAt: Date? = UserDefaults.standard.object(forKey: "syncLastSyncedAt") as? Date {
        didSet { UserDefaults.standard.set(lastSyncedAt, forKey: "syncLastSyncedAt") }
    }

    private var runAgain = false

    /// Runs one sync for the signed-in user (no-op when signed out). Calls while a sync is running
    /// coalesce into one more pass afterwards.
    func sync(_ context: ModelContext) async {
        guard let store = RemoteStore.current() else { return }
        if phase == .syncing {
            runAgain = true
            return
        }
        phase = .syncing
        prepare(for: store.userID, context: context)
        do {
            try await pull(store, context)
            try await push(store, context)
            await syncImages(store, context)
            try context.save()
            lastSyncedAt = Date()
            phase = .idle
        } catch {
            phase = .failed(error.localizedDescription)
        }
        if runAgain {
            runAgain = false
            await sync(context)
        }
    }

    /// Forgets what was synced (on sign-out). Local data stays on the device.
    func reset(_ context: ModelContext) {
        ((try? context.fetch(FetchDescriptor<SyncRecord>())) ?? []).forEach { context.delete($0) }
        try? context.save()
        for table in SyncTable.allCases { UserDefaults.standard.removeObject(forKey: cursorKey(table)) }
        UserDefaults.standard.removeObject(forKey: Self.userKey)
        lastSyncedAt = nil
        phase = .idle
    }

    // MARK: - Bookkeeping

    private static let userKey = "syncUserID"

    private func cursorKey(_ table: SyncTable) -> String { "syncCursor.\(table.rawValue)" }

    private func cursor(_ table: SyncTable) -> Date? {
        UserDefaults.standard.object(forKey: cursorKey(table)) as? Date
    }

    private func setCursor(_ date: Date?, _ table: SyncTable) {
        guard let date else { return }
        if let current = cursor(table), current >= date { return }
        UserDefaults.standard.set(date, forKey: cursorKey(table))
    }

    /// A different account than last time: start over so nothing leaks between accounts.
    private func prepare(for userID: UUID, context: ModelContext) {
        let previous = UserDefaults.standard.string(forKey: Self.userKey)
        if previous != userID.uuidString {
            if previous != nil { reset(context) }
            UserDefaults.standard.set(userID.uuidString, forKey: Self.userKey)
        }
    }

    private func loadRecords(_ context: ModelContext) throws -> [String: SyncRecord] {
        let all = try context.fetch(FetchDescriptor<SyncRecord>())
        return Dictionary(all.map { ($0.recordKey, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private static func recordKey(_ table: SyncTable, _ id: String) -> String { "\(table.rawValue):\(id)" }
    private static func imageKey(_ name: String) -> String { "image:\(name)" }

    private func record(_ key: String, fingerprint: String, in records: inout [String: SyncRecord], context: ModelContext) {
        if let existing = records[key] {
            existing.fingerprint = fingerprint
            existing.syncedAt = Date()
        } else {
            let new = SyncRecord(recordKey: key, fingerprint: fingerprint)
            context.insert(new)
            records[key] = new
        }
    }

    private func forget(_ key: String, in records: inout [String: SyncRecord], context: ModelContext) {
        if let existing = records.removeValue(forKey: key) { context.delete(existing) }
    }

    private enum Decision {
        /// Take the server's version (create, update).
        case apply
        /// The server deleted it and we have no unsynced edits.
        case delete
        /// Already identical: just remember that.
        case same
        /// Keep ours (unsynced local edits, or a local deletion waiting to be pushed).
        case keepLocal
        /// Nothing to do and nothing to remember.
        case ignore
    }

    private func decide(remote: some SyncRow, local: String?, record: SyncRecord?) -> Decision {
        let deleted = remote.deletedAt != nil
        guard let local else {
            if deleted { return .ignore }
            // We had it and deleted it locally: our deletion gets pushed next.
            return record == nil ? .apply : .keepLocal
        }
        if !deleted, local == remote.fingerprint { return .same }
        // Never synced (e.g. demo data present on both sides) counts as clean: the server wins.
        let clean = record.map { $0.fingerprint == local } ?? true
        guard clean else { return .keepLocal }
        return deleted ? .delete : .apply
    }

    // MARK: - Pull

    private func pull(_ store: RemoteStore, _ context: ModelContext) async throws {
        var records = try loadRecords(context)
        let userID = store.userID

        // Collections
        let collectionChanges = try await store.changes(CollectionRow.self, since: cursor(.collections))
        var collections = Dictionary(try context.fetch(FetchDescriptor<TasteCollection>()).map { ($0.id, $0) },
                                     uniquingKeysWith: { first, _ in first })
        for change in collectionChanges {
            let row = change.row
            let key = Self.recordKey(.collections, row.rowID)
            let local = collections[row.id]
            switch decide(remote: row, local: local?.row(userID: userID).fingerprint, record: records[key]) {
            case .apply:
                let collection: TasteCollection
                if let local {
                    collection = local
                } else {
                    collection = TasteCollection(name: row.name)
                    collection.id = row.id
                    context.insert(collection)
                    collections[row.id] = collection
                }
                collection.apply(row)
                record(key, fingerprint: row.fingerprint, in: &records, context: context)
            case .delete:
                if let local {
                    context.delete(local)
                    collections[row.id] = nil
                }
                forget(key, in: &records, context: context)
            case .same:
                record(key, fingerprint: row.fingerprint, in: &records, context: context)
            case .keepLocal, .ignore:
                break
            }
        }
        setCursor(collectionChanges.last?.updatedAt, .collections)

        // Saves
        let saveChanges = try await store.changes(SaveRow.self, since: cursor(.saves))
        var saves = Dictionary(try context.fetch(FetchDescriptor<SaveItem>()).map { ($0.id, $0) },
                               uniquingKeysWith: { first, _ in first })
        for change in saveChanges {
            let row = change.row
            let key = Self.recordKey(.saves, row.rowID)
            let local = saves[row.id]
            switch decide(remote: row, local: local?.row(userID: userID).fingerprint, record: records[key]) {
            case .apply:
                let item: SaveItem
                if let local {
                    item = local
                } else {
                    item = SaveItem(kind: ItemKind(rawValue: row.kind) ?? .photo)
                    item.id = row.id
                    context.insert(item)
                    saves[row.id] = item
                }
                item.apply(row, collection: row.collectionID.flatMap { collections[$0] })
                record(key, fingerprint: row.fingerprint, in: &records, context: context)
            case .delete:
                if let local {
                    if let fileName = local.imageFileName { ImageStore.delete(named: fileName) }
                    context.delete(local)
                    saves[row.id] = nil
                }
                forget(key, in: &records, context: context)
            case .same:
                record(key, fingerprint: row.fingerprint, in: &records, context: context)
            case .keepLocal, .ignore:
                break
            }
        }
        setCursor(saveChanges.last?.updatedAt, .saves)

        // Tags
        let tagChanges = try await store.changes(TagRow.self, since: cursor(.tags))
        let tags = Dictionary(try context.fetch(FetchDescriptor<TagEntry>()).map { ($0.id, $0) },
                              uniquingKeysWith: { first, _ in first })
        for change in tagChanges {
            let row = change.row
            let key = Self.recordKey(.tags, row.rowID)
            let local = tags[row.id]
            switch decide(remote: row, local: local?.row(userID: userID).fingerprint, record: records[key]) {
            case .apply:
                let tag: TagEntry
                if let local {
                    tag = local
                } else {
                    tag = TagEntry(name: row.name, level: TagLevel(rawValue: row.level) ?? .ingredient,
                                   status: TagStatus(rawValue: row.status) ?? .suggested,
                                   source: TagSource(rawValue: row.source) ?? .user)
                    tag.id = row.id
                    context.insert(tag)
                }
                tag.apply(row, item: row.saveID.flatMap { saves[$0] })
                record(key, fingerprint: row.fingerprint, in: &records, context: context)
            case .delete:
                if let local { context.delete(local) }
                forget(key, in: &records, context: context)
            case .same:
                record(key, fingerprint: row.fingerprint, in: &records, context: context)
            case .keepLocal, .ignore:
                break
            }
        }
        setCursor(tagChanges.last?.updatedAt, .tags)

        // Learn cards
        let cardChanges = try await store.changes(LearnCardRow.self, since: cursor(.learnCards))
        let cards = Dictionary(try context.fetch(FetchDescriptor<LearnCardRecord>()).map { ($0.key, $0) },
                               uniquingKeysWith: { first, _ in first })
        for change in cardChanges {
            let row = change.row
            let key = Self.recordKey(.learnCards, row.rowID)
            let local = cards[row.key]
            switch decide(remote: row, local: local?.row(userID: userID)?.fingerprint, record: records[key]) {
            case .apply:
                if let local {
                    local.update(row.payload, origin: row.origin)
                } else {
                    context.insert(LearnCardRecord(key: row.key, content: row.payload, origin: row.origin))
                }
                record(key, fingerprint: row.fingerprint, in: &records, context: context)
            case .delete:
                if let local { context.delete(local) }
                forget(key, in: &records, context: context)
            case .same:
                record(key, fingerprint: row.fingerprint, in: &records, context: context)
            case .keepLocal, .ignore:
                break
            }
        }
        setCursor(cardChanges.last?.updatedAt, .learnCards)

        try context.save()
    }

    // MARK: - Push

    private func push(_ store: RemoteStore, _ context: ModelContext) async throws {
        var records = try loadRecords(context)
        let userID = store.userID

        try await push(try context.fetch(FetchDescriptor<TasteCollection>()).map { $0.row(userID: userID) },
                       store: store, records: &records, context: context)
        try await push(try context.fetch(FetchDescriptor<SaveItem>()).map { $0.row(userID: userID) },
                       store: store, records: &records, context: context)
        try await push(try context.fetch(FetchDescriptor<TagEntry>()).map { $0.row(userID: userID) },
                       store: store, records: &records, context: context)
        try await push(try context.fetch(FetchDescriptor<LearnCardRecord>()).compactMap { $0.row(userID: userID) },
                       store: store, records: &records, context: context)
        try context.save()
    }

    private func push<Row: SyncRow>(_ rows: [Row], store: RemoteStore, records: inout [String: SyncRecord],
                                    context: ModelContext) async throws {
        let table = Row.table
        let changed = rows.filter { records[Self.recordKey(table, $0.rowID)]?.fingerprint != $0.fingerprint }
        try await store.upsert(changed)
        for row in changed {
            record(Self.recordKey(table, row.rowID), fingerprint: row.fingerprint, in: &records, context: context)
        }

        let prefix = "\(table.rawValue):"
        let present = Set(rows.map { Self.recordKey(table, $0.rowID) })
        let gone = records.keys.filter { $0.hasPrefix(prefix) && !present.contains($0) }
        try await store.markDeleted(table, ids: gone.map { String($0.dropFirst(prefix.count)) })
        for key in gone { forget(key, in: &records, context: context) }
    }

    // MARK: - Images

    /// Uploads images we have that the server doesn't, and downloads ones we're missing.
    /// Failures are retried next sync (they never fail the whole sync).
    private func syncImages(_ store: RemoteStore, _ context: ModelContext) async {
        guard var records = try? loadRecords(context) else { return }
        let items = (try? context.fetch(FetchDescriptor<SaveItem>())) ?? []
        let collections = (try? context.fetch(FetchDescriptor<TasteCollection>())) ?? []
        let names = Set(items.compactMap(\.imageFileName) + collections.flatMap(\.coverImageNames))
        let pending = names.filter { records[Self.imageKey($0)] == nil }.sorted()

        var done: [String] = []
        for batch in stride(from: 0, to: pending.count, by: 4).map({ Array(pending[$0..<min($0 + 4, pending.count)]) }) {
            let finished = await withTaskGroup(of: String?.self) { group in
                for name in batch {
                    group.addTask {
                        do {
                            if let data = ImageStore.data(named: name) {
                                try await store.uploadImage(named: name, data: data)
                            } else {
                                let data = try await store.downloadImage(named: name)
                                guard ImageStore.store(data: data, named: name) else { return nil }
                            }
                            return name
                        } catch {
                            return nil
                        }
                    }
                }
                var names: [String] = []
                for await name in group { if let name { names.append(name) } }
                return names
            }
            done += finished
        }
        for name in done { record(Self.imageKey(name), fingerprint: "1", in: &records, context: context) }
    }
}

// MARK: - Row mapping

extension TasteCollection {
    func row(userID: UUID) -> CollectionRow {
        CollectionRow(
            id: id, userID: userID, name: name, domain: domain, verb: verb, symbol: symbol, sortIndex: sortIndex,
            statement: statement, statementSignature: statementSignature, source: sourceRaw, sourceID: sourceID,
            sourceURL: sourceURL, sourceItemCount: sourceItemCount, importedAt: importedAt, summary: summary,
            profile: importedProfile, coverImages: coverImageNames, createdAt: createdAt, deletedAt: nil
        )
    }

    func apply(_ row: CollectionRow) {
        name = row.name
        domain = row.domain
        verb = row.verb
        symbol = row.symbol
        sortIndex = row.sortIndex
        statement = row.statement
        statementSignature = row.statementSignature
        sourceRaw = row.source
        sourceID = row.sourceID
        sourceURL = row.sourceURL
        sourceItemCount = row.sourceItemCount
        importedAt = row.importedAt
        summary = row.summary
        importedProfile = row.profile
        coverImageNames = row.coverImages
        createdAt = row.createdAt
    }
}

extension SaveItem {
    func row(userID: UUID) -> SaveRow {
        SaveRow(
            id: id, userID: userID, collectionID: collection?.id, kind: kindRaw, title: title, note: note,
            url: urlString, imageName: imageFileName, artStyle: artStyleRaw, artSeed: artSeed, why: why,
            decodedAt: decodedAt, createdAt: createdAt, deletedAt: nil
        )
    }

    func apply(_ row: SaveRow, collection: TasteCollection?) {
        kindRaw = row.kind
        title = row.title
        note = row.note
        urlString = row.url
        imageFileName = row.imageName
        artStyleRaw = row.artStyle
        artSeed = row.artSeed
        why = row.why
        decodedAt = row.decodedAt
        createdAt = row.createdAt
        self.collection = collection
    }
}

extension TagEntry {
    func row(userID: UUID) -> TagRow {
        TagRow(id: id, userID: userID, saveID: item?.id, name: name, key: key, level: levelRaw, status: statusRaw,
               source: sourceRaw, createdAt: createdAt, deletedAt: nil)
    }

    func apply(_ row: TagRow, item: SaveItem?) {
        name = row.name
        key = row.key
        levelRaw = row.level
        statusRaw = row.status
        sourceRaw = row.source
        createdAt = row.createdAt
        self.item = item
    }
}

extension LearnCardRecord {
    func row(userID: UUID) -> LearnCardRow? {
        guard let content else { return nil }
        return LearnCardRow(key: key, userID: userID, payload: content, origin: origin, deletedAt: nil)
    }
}
