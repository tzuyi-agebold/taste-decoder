import CryptoKit
import Foundation
import SwiftData

/// The four worked examples, preloaded so the app demonstrates itself on first open.
enum SeedData {
    static let version = 1
    private static let versionKey = "seedDataVersion"

    struct Item {
        let title: String
        var why: String? = nil
        let feelings: [String]
        let references: [String]
        let ingredients: [String]
    }

    struct Collection {
        let name: String
        let domain: String
        let verb: String
        let symbol: String
        let art: ArtStyle
        let statement: String
        let items: [Item]
    }

    static let collections: [Collection] = [
        Collection(
            name: "Uncomfy", domain: "visuals", verb: "feel", symbol: "eye", art: .uncomfy,
            statement: "I like visuals that feel uncomfortable — distortion, flash lighting, acidic color.",
            items: [
                Item(title: "Stretched portrait, ring flash", why: "Couldn't look away. It's wrong in a good way.",
                     feelings: ["uncomfortable", "uneasy"], references: ["David Lynch"],
                     ingredients: ["distorted proportions", "harsh flash lighting", "acidic color"]),
                Item(title: "Fisheye party snapshot", why: "The flash makes everyone look caught.",
                     feelings: ["electric", "uncomfortable"], references: ["90s rave flyer"],
                     ingredients: ["harsh flash lighting", "fisheye lens", "distorted proportions"]),
                Item(title: "Acid-green still life",
                     feelings: ["uncomfortable", "off-kilter"], references: ["Juergen Teller"],
                     ingredients: ["acidic color", "harsh flash lighting", "film grain"]),
                Item(title: "Melting face collage",
                     feelings: ["uneasy"], references: ["Francis Bacon"],
                     ingredients: ["distorted proportions", "hand-drawn mixed media", "acidic color"]),
                Item(title: "Direct-flash street portrait", why: "She's staring right through the lens.",
                     feelings: ["uncomfortable", "electric"], references: ["Juergen Teller"],
                     ingredients: ["harsh flash lighting", "film grain", "direct eye contact"]),
                Item(title: "Warped mirror selfie",
                     feelings: ["off-kilter", "uncomfortable"], references: ["David Lynch"],
                     ingredients: ["distorted proportions", "harsh flash lighting", "acidic color"]),
                Item(title: "Neon hallway at 3am",
                     feelings: ["late-night", "uneasy"], references: ["David Lynch"],
                     ingredients: ["acidic color", "harsh flash lighting", "film grain"]),
                Item(title: "Stretched product shot",
                     feelings: ["uncomfortable"], references: [],
                     ingredients: ["distorted proportions", "acidic color", "harsh flash lighting"]),
                Item(title: "Blurry club crowd",
                     feelings: ["electric", "late-night"], references: ["90s rave flyer"],
                     ingredients: ["harsh flash lighting", "motion blur", "distorted proportions"]),
                Item(title: "Uncanny doll close-up", why: "Too close. Too bright. I love it.",
                     feelings: ["uncomfortable", "uneasy"], references: ["David Lynch"],
                     ingredients: ["harsh flash lighting", "distorted proportions", "film grain"]),
            ]
        ),
        Collection(
            name: "Reds I Love", domain: "reds", verb: "taste", symbol: "wineglass", art: .wine,
            statement: "I like reds that taste like a campfire library — caramel, toasted oak, leather.",
            items: [
                Item(title: "Rioja Gran Reserva", why: "Tasted like a library with a fireplace.",
                     feelings: ["warm", "cozy"], references: ["campfire library"],
                     ingredients: ["toasted oak", "leather", "vanilla", "caramel"]),
                Item(title: "Napa Valley Cabernet Sauvignon",
                     feelings: ["warm", "brooding"], references: [],
                     ingredients: ["toasted oak", "caramel", "dark cherry", "vanilla"]),
                Item(title: "Barolo",
                     feelings: ["brooding"], references: ["old bookshop"],
                     ingredients: ["leather", "tobacco", "dried fig", "toasted oak"]),
                Item(title: "Châteauneuf-du-Pape", why: "Like sinking into an old armchair.",
                     feelings: ["warm", "cozy"], references: ["grandpa's leather armchair"],
                     ingredients: ["leather", "caramel", "dried fig", "velvety tannins"]),
                Item(title: "Ribera del Duero Crianza",
                     feelings: ["warm"], references: ["campfire library"],
                     ingredients: ["toasted oak", "caramel", "smoke", "dark cherry"]),
                Item(title: "Pauillac (Bordeaux)",
                     feelings: ["brooding", "cozy"], references: ["grandpa's leather armchair"],
                     ingredients: ["tobacco", "leather", "toasted oak", "caramel"]),
                Item(title: "Old-vine Zinfandel",
                     feelings: ["warm", "cozy"], references: [],
                     ingredients: ["caramel", "vanilla", "dark cherry", "toasted oak"]),
                Item(title: "Northern Rhône Syrah",
                     feelings: ["brooding", "warm"], references: ["campfire library", "old bookshop"],
                     ingredients: ["smoke", "leather", "toasted oak", "tobacco"]),
            ]
        ),
        Collection(
            name: "Rooms", domain: "rooms", verb: "feel", symbol: "sofa", art: .room,
            statement: "I like rooms that feel like a lamp-lit hideout — walnut wood, low-profile seating, warm directional lighting, no overhead lights.",
            items: [
                Item(title: "Walnut-paneled den", why: "The room is holding you.",
                     feelings: ["cozy", "warm"], references: ["mid-century modern"],
                     ingredients: ["walnut wood", "warm directional lighting", "no overhead lights", "leather"]),
                Item(title: "Low sofa, one floor lamp",
                     feelings: ["calm", "cozy"], references: [],
                     ingredients: ["low-profile seating", "warm directional lighting", "no overhead lights", "linen"]),
                Item(title: "Jazz kissa corner, Tokyo", why: "Everyone whispering, records glowing.",
                     feelings: ["intimate", "warm"], references: ["Tokyo jazz kissa"],
                     ingredients: ["walnut wood", "warm directional lighting", "no overhead lights", "low-profile seating"]),
                Item(title: "Cabin reading nook",
                     feelings: ["cozy"], references: [],
                     ingredients: ["walnut wood", "warm directional lighting", "linen", "low-profile seating"]),
                Item(title: "70s conversation pit",
                     feelings: ["warm", "intimate"], references: ["70s conversation pit"],
                     ingredients: ["low-profile seating", "walnut wood", "brass accents", "leather"]),
                Item(title: "Candlelit dining room",
                     feelings: ["cozy", "calm"], references: ["Tokyo jazz kissa"],
                     ingredients: ["warm directional lighting", "no overhead lights", "walnut wood", "brass accents"]),
                Item(title: "Mid-century living room",
                     feelings: ["calm", "warm"], references: ["mid-century modern"],
                     ingredients: ["walnut wood", "low-profile seating", "warm directional lighting", "leather"]),
                Item(title: "Bedroom, lamps only",
                     feelings: ["cozy", "warm"], references: ["Tokyo jazz kissa"],
                     ingredients: ["low-profile seating", "warm directional lighting", "no overhead lights", "linen"]),
            ]
        ),
        Collection(
            name: "2am Songs", domain: "songs", verb: "feel", symbol: "music.note", art: .night,
            statement: "I like songs that feel like 2am — minor keys, brushed drums, everything swimming in reverb.",
            items: [
                Item(title: "Sodium Light — Hollis Vale", why: "Driving home while the city sleeps.",
                     feelings: ["late-night", "melancholy"], references: ["2am drive home", "Mazzy Star"],
                     ingredients: ["minor keys", "reverb-heavy", "breathy female vocal", "brushed drums"]),
                Item(title: "Paper Moon Motel — The Low Hours",
                     feelings: ["intimate", "late-night"], references: ["Wong Kar-wai"],
                     ingredients: ["brushed drums", "upright bass", "90–100 BPM", "reverb-heavy"]),
                Item(title: "Glasshouse — June Arden",
                     feelings: ["hazy", "melancholy"], references: ["Mazzy Star"],
                     ingredients: ["breathy female vocal", "reverb-heavy", "minor keys", "tape hiss"]),
                Item(title: "Nightbus Hymn — Ottoline",
                     feelings: ["late-night", "intimate"], references: ["2am drive home"],
                     ingredients: ["minor keys", "90–100 BPM", "Rhodes piano", "breathy female vocal"]),
                Item(title: "Velvet Static — Marisol Kite", why: "Like a dream you can't quite remember.",
                     feelings: ["hazy", "late-night"], references: ["David Lynch"],
                     ingredients: ["reverb-heavy", "tape hiss", "minor keys", "breathy female vocal"]),
                Item(title: "After the Rain Stops — Nell & the Quiet",
                     feelings: ["melancholy", "intimate"], references: ["Wong Kar-wai", "2am drive home"],
                     ingredients: ["brushed drums", "90–100 BPM", "Rhodes piano", "reverb-heavy"]),
                Item(title: "Slow Dissolve — Harbor Lights Trio",
                     feelings: ["late-night", "hazy"], references: ["David Lynch"],
                     ingredients: ["minor keys", "brushed drums", "upright bass", "reverb-heavy"]),
                Item(title: "Four in the Morning — Ada Lune",
                     feelings: ["melancholy", "intimate"], references: ["Mazzy Star", "2am drive home"],
                     ingredients: ["breathy female vocal", "90–100 BPM", "reverb-heavy", "minor keys", "Rhodes piano", "brushed drums"]),
            ]
        ),
    ]

    /// Undecoded saves waiting in the inbox, to demo the interrogation loop.
    static let inbox: [(title: String?, note: String?, art: ArtStyle?)] = [
        ("Poster from a café wall", nil, .riso),
        (nil, "The hotel lobby in that Sofia Coppola film — the hush, the jet lag, the neon.", nil),
    ]

    /// Demo rows get the same ids on every device, so syncing two devices merges the demo instead of doubling it.
    static func seededID(_ name: String) -> UUID {
        let bytes = Array(SHA256.hash(data: Data("taste-decoder-seed|\(name)".utf8)).prefix(16))
        var uuid = bytes
        uuid[6] = (uuid[6] & 0x0F) | 0x50 // version 5-style
        uuid[8] = (uuid[8] & 0x3F) | 0x80 // RFC 4122 variant
        return UUID(uuid: (uuid[0], uuid[1], uuid[2], uuid[3], uuid[4], uuid[5], uuid[6], uuid[7],
                           uuid[8], uuid[9], uuid[10], uuid[11], uuid[12], uuid[13], uuid[14], uuid[15]))
    }

    @MainActor
    static func seedIfNeeded(_ context: ModelContext) {
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: versionKey) < version else { return }
        let existing = (try? context.fetchCount(FetchDescriptor<TasteCollection>())) ?? 0
        if existing == 0 { insertAll(context) }
        defaults.set(version, forKey: versionKey)
    }

    /// Inserts any seed collection that's missing (matched by name), plus the inbox demo saves.
    @MainActor
    static func insertAll(_ context: ModelContext, includeInbox: Bool = true) {
        let existingNames = Set(((try? context.fetch(FetchDescriptor<TasteCollection>())) ?? []).map(\.name))
        let now = Date()

        for (collectionIndex, seed) in collections.enumerated() where !existingNames.contains(seed.name) {
            let collection = TasteCollection(name: seed.name, domain: seed.domain, verb: seed.verb,
                                             symbol: seed.symbol, sortIndex: collectionIndex)
            collection.id = seededID("collection|\(seed.name)")
            collection.createdAt = now.addingTimeInterval(TimeInterval(-86_400 * (30 - collectionIndex)))
            context.insert(collection)

            for (itemIndex, seedItem) in seed.items.enumerated() {
                let created = now.addingTimeInterval(TimeInterval(-86_400 * (28 - collectionIndex * 5) + itemIndex * 3_600))
                let item = SaveItem(kind: .photo, title: seedItem.title, createdAt: created)
                item.artStyleRaw = seed.art.rawValue
                item.artSeed = collectionIndex * 100 + itemIndex
                item.why = seedItem.why
                item.decodedAt = created.addingTimeInterval(600)
                item.id = seededID("item|\(seed.name)|\(itemIndex)")
                context.insert(item)
                item.collection = collection

                let levels: [(TagLevel, [String])] = [
                    (.feeling, seedItem.feelings), (.reference, seedItem.references), (.ingredient, seedItem.ingredients),
                ]
                for (level, names) in levels {
                    for name in names {
                        context.addTag(name, level: level, to: item)?.id = seededID("tag|\(seed.name)|\(itemIndex)|\(level.rawValue)|\(name)")
                    }
                }
            }

            // Computed from the seed definitions so it doesn't depend on inverse relationships updating mid-insert.
            let snapshots = seed.items.map { seedItem in
                ItemSnapshot(id: UUID(), tags: seedItem.feelings.map { TagSnapshot(name: $0, level: .feeling) }
                    + seedItem.references.map { TagSnapshot(name: $0, level: .reference) }
                    + seedItem.ingredients.map { TagSnapshot(name: $0, level: .ingredient) })
            }
            collection.statement = seed.statement
            collection.statementSignature = Distiller.distill(snapshots).signature
        }

        if includeInbox {
            for (index, seed) in inbox.enumerated() {
                let item = SaveItem(kind: seed.art == nil ? .note : .photo, title: seed.title, note: seed.note,
                                    createdAt: now.addingTimeInterval(TimeInterval(-600 * (index + 1))))
                item.artStyleRaw = seed.art?.rawValue
                item.artSeed = 900 + index
                item.id = seededID("inbox|\(index)")
                context.insert(item)
            }
        }
        try? context.save()
    }

    /// Deletes everything (saves, collections, tags, cached cards, images) and re-seeds.
    @MainActor
    static func resetAll(_ context: ModelContext) {
        let items = (try? context.fetch(FetchDescriptor<SaveItem>())) ?? []
        let images = items.compactMap(\.imageFileName)
        // Object-by-object deletes keep live views and relationships consistent.
        items.forEach { context.delete($0) }
        ((try? context.fetch(FetchDescriptor<TagEntry>())) ?? []).forEach { context.delete($0) }
        ((try? context.fetch(FetchDescriptor<TasteCollection>())) ?? []).forEach { context.delete($0) }
        ((try? context.fetch(FetchDescriptor<LearnCardRecord>())) ?? []).forEach { context.delete($0) }
        try? context.save()
        images.forEach(ImageStore.delete(named:))
        insertAll(context)
    }
}
