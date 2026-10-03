import Foundation

// The three Claude-powered features. Counting and ranking are always done locally
// (see Distiller); Claude only proposes tags, writes prose and explains terms.

// MARK: - Tag suggestions (vision)

struct TagSuggestions: Decodable {
    var feelings: [String]
    var references: [String]
    var ingredients: [String]

    func names(for level: TagLevel) -> [String] {
        switch level {
        case .feeling: feelings
        case .reference: references
        case .ingredient: ingredients
        }
    }
}

struct SuggestionContext {
    var imageJPEG: Data?
    var title: String?
    var note: String?
    var urlString: String?
    var why: String?
    var collectionName: String?
    var domain: String?
    /// The user's most-used tags per level, offered so patterns can form.
    var vocabulary: [TagLevel: [String]] = [:]
    /// Tags already on the item in any state (including rejected), not to be repeated.
    var existing: [String] = []

    var hasSomethingToLookAt: Bool {
        imageJPEG != nil || [title, note, urlString, why].contains { !($0 ?? "").isEmpty }
    }
}

enum TagSuggester {
    private static let system = """
    You help people articulate their taste in an app called Taste Decoder. Someone saved the thing below \
    because something about it appealed to them. Suggest candidate tags on three levels of an articulation ladder:
    - feelings: plain emotional words anyone can use ("uncomfortable", "cozy", "electric", "melancholy").
    - references: similes, metaphors or cultural references that capture it ("a Michel Gondry movie", \
    "90s skate zine", "a campfire library"). Name real people, works, eras or scenes only when you're confident they fit.
    - ingredients: the specific techniques, elements, materials, mediums or tasting notes a practitioner would name \
    ("harsh flash lighting", "hand-drawn mixed media", "toasted oak", "brushed drums"). This is the most important \
    level: be concrete and observable, never evaluative ("beautiful" is not an ingredient).
    Rules: 1–4 words per tag. Lowercase unless it's a proper noun. No duplicates across levels. Don't repeat tags \
    the person already has. When one of the person's existing vocabulary words genuinely fits, reuse its exact \
    wording so patterns can emerge across their saves. Give 3–4 feelings, 2–3 references and 4–6 ingredients.
    """

    private static let schema = JSONSchema.object([
        ("feelings", JSONSchema.array(JSONSchema.string())),
        ("references", JSONSchema.array(JSONSchema.string())),
        ("ingredients", JSONSchema.array(JSONSchema.string())),
    ])

    static func suggest(_ context: SuggestionContext, client: ClaudeClient) async throws -> TagSuggestions {
        var lines: [String] = []
        if context.imageJPEG != nil { lines.append("The saved image is attached.") }
        if let title = context.title, !title.isEmpty { lines.append("Title: \(title)") }
        if let url = context.urlString, !url.isEmpty { lines.append("Saved from: \(url)") }
        if let note = context.note, !note.isEmpty { lines.append("Note: \(note)") }
        if let why = context.why, !why.isEmpty { lines.append("Why they saved it, in their words: \(why)") }
        if let collection = context.collectionName {
            lines.append("It's in their collection “\(collection)”\(context.domain.map { " (\($0))" } ?? "").")
        }
        for level in TagLevel.allCases {
            if let words = context.vocabulary[level], !words.isEmpty {
                lines.append("Their existing \(level.pluralTitle.lowercased()): \(words.joined(separator: ", "))")
            }
        }
        if !context.existing.isEmpty {
            lines.append("Already tagged (don't repeat): \(context.existing.joined(separator: ", "))")
        }
        lines.append("Suggest tags.")

        let images = context.imageJPEG.map { [ClaudeClient.ImageInput(data: $0)] } ?? []
        let result = try await client.structured(TagSuggestions.self, system: system, prompt: lines.joined(separator: "\n"),
                                                 images: images, schema: schema, effort: .low, maxTokens: 4_000, timeout: 90)
        return result
    }
}

// MARK: - Taste statements (prose only)

enum TasteStatementWriter {
    private struct Output: Decodable { let statement: String }

    private static let system = """
    You write one-sentence taste statements for Taste Decoder. The person's saves have already been counted; \
    you only turn the counts into a sentence they could say out loud to a friend or a collaborator.
    Shape: "I like [domain] that [verb] [feeling or a vivid metaphor built from their feelings and references] — \
    [3–5 of their recurring ingredients, comma-separated]."
    Examples:
    "I like visuals that feel uncomfortable — distortion, flash lighting, acidic color."
    "I like reds that taste like a campfire library — caramel, toasted oak, leather."
    "I like songs that feel like 2am — minor keys, brushed drums, everything swimming in reverb."
    Use their own ingredient words (you may shorten them slightly). Keep the most frequent ones. Under 28 words. \
    No hype, no hedging, no quotation marks.
    """

    private static let schema = JSONSchema.object([("statement", JSONSchema.string())])

    static func write(collectionName: String, domain: String, verb: String, distillation: Distillation,
                      client: ClaudeClient) async throws -> String {
        func describe(_ counts: [TagCount]) -> String {
            counts.prefix(6).map { "\($0.name) (\($0.count) of \($0.total))" }.joined(separator: ", ")
        }
        let prompt = """
        Collection: \(collectionName)
        Domain: \(domain)
        Verb: \(verb)
        Feelings: \(describe(distillation.feelings))
        References: \(describe(distillation.references))
        Recurring ingredients: \(describe(distillation.signatureIngredients))
        Write the statement.
        """
        let output = try await client.structured(Output.self, system: system, prompt: prompt, schema: schema,
                                                 effort: .low, maxTokens: 2_000, timeout: 60)
        return output.statement
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"“”"))
    }
}

// MARK: - Learn cards

enum LearnCardGenerator {
    private struct Output: Decodable {
        struct Example: Decodable { let title: String; let detail: String }
        struct Link: Decodable { let name: String; let kind: String }
        let title: String
        let kind: String
        let summary: String
        let era: String
        let characteristics: [String]
        let examples: [Example]
        let encounter: String
        let why_it_matters: String
        let related: [Link]
    }

    private static let system = """
    You write Learn cards for Taste Decoder, an app that helps people articulate their taste. A card teaches the \
    person, style or term behind one of their tags, in plain language for a curious non-expert.
    Accuracy matters more than completeness: name only real people, works and dates you're confident about; \
    if unsure of a year, leave it out. No filler, no hype.
    Choose kind:
    - person (a real person, band or studio): summary = one-line bio; era = their era or movement; \
    characteristics = 3–4 signature traits; examples = exactly 3 signature works, year in the title, e.g. \
    "Eternal Sunshine of the Spotless Mind (2004)".
    - style (a style, movement, genre or scene): summary = plain-language definition; era = when it emerged; \
    characteristics = 3–4 defining characteristics; examples = 3 canonical examples.
    - term (a technique, material, element, tasting note, feeling or metaphor): summary = what it means; \
    characteristics = 3–4 ways to recognize it (what it looks, sounds or tastes like); examples = 3 places you'd meet it; \
    encounter = one sentence on where you'd encounter it in the wild. Use an empty era if none applies.
    Example details are one short sentence. why_it_matters = one sentence on why it matters to someone whose taste \
    includes it, using the context given. related = 4–6 people, styles or terms to explore next, mixing kinds.
    """

    private static let schema: [String: Any] = {
        let kinds = JSONSchema.stringEnum(LearnKind.allCases.map(\.rawValue))
        return JSONSchema.object([
            ("title", JSONSchema.string()),
            ("kind", kinds),
            ("summary", JSONSchema.string()),
            ("era", JSONSchema.string()),
            ("characteristics", JSONSchema.array(JSONSchema.string())),
            ("examples", JSONSchema.array(JSONSchema.object([("title", JSONSchema.string()), ("detail", JSONSchema.string())]))),
            ("encounter", JSONSchema.string()),
            ("why_it_matters", JSONSchema.string()),
            ("related", JSONSchema.array(JSONSchema.object([("name", JSONSchema.string()), ("kind", kinds)]))),
        ])
    }()

    /// - Parameters:
    ///   - usage: how the user uses the tag, e.g. "an ingredient in Uncomfy (6 saves)".
    ///   - neighbors: tags that appear alongside it in their saves.
    static func generate(topic: String, usage: String?, neighbors: [String], client: ClaudeClient) async throws -> LearnCardContent {
        var prompt = "Topic: \(topic)"
        if let usage { prompt += "\nHow they use it: \(usage)" }
        if !neighbors.isEmpty { prompt += "\nIt appears alongside: \(neighbors.prefix(10).joined(separator: ", "))" }
        prompt += "\nWrite the card."

        let output = try await client.structured(Output.self, system: system, prompt: prompt, schema: schema,
                                                 effort: .medium, maxTokens: 8_000, timeout: 150)
        return LearnCardContent(
            title: output.title.isEmpty ? topic : output.title,
            kind: LearnKind(rawValue: output.kind) ?? .term,
            aliases: TagText.key(output.title) == TagText.key(topic) ? [] : [topic],
            summary: output.summary,
            era: output.era,
            characteristics: output.characteristics,
            examples: output.examples.map { LearnExample(title: $0.title, detail: $0.detail) },
            encounter: output.encounter,
            whyItMatters: output.why_it_matters,
            related: output.related.map { LearnLink(name: $0.name, kind: LearnKind(rawValue: $0.kind) ?? .term) }
        )
    }
}

// MARK: - Board summaries (imported collections)

/// What Claude makes of a whole Pinterest board: a summary and tag counts over the pins it looked at.
struct BoardSummary: Sendable {
    var about: String
    var domain: String
    var verb: String
    var statement: String
    var symbol: String
    var profile: ImportedProfile
}

enum BoardAnalyzer {
    /// Symbols offered to Claude; the same set the collection editor uses.
    static let symbols = ["square.stack", "eye", "camera", "paintpalette", "wineglass", "fork.knife", "sofa",
                          "music.note", "film", "book", "tshirt", "leaf", "building.2", "sparkles"]
    static let verbs = ["feel", "look", "sound", "taste", "read"]

    private struct Output: Decodable {
        struct Count: Decodable { let name: String; let count: Int }
        let about: String
        let domain: String
        let verb: String
        let symbol: String
        let feelings: [Count]
        let references: [Count]
        let ingredients: [Count]
        let statement: String
    }

    private static let system = """
    You help people articulate their taste in an app called Taste Decoder. Someone imported one of their Pinterest \
    boards. You see a sample of its pins as numbered images, plus the titles and descriptions of every pin. \
    Work out what the board is about and what keeps showing up, on three levels of an articulation ladder:
    - feelings: plain emotional words anyone can use ("uncomfortable", "cozy", "electric", "melancholy").
    - references: similes, metaphors or cultural references that capture it ("a Wes Anderson set", "90s skate zine"). \
    Name real people, works, eras or scenes only when you're confident they fit.
    - ingredients: the specific techniques, elements, materials, colors, shapes or textures a practitioner would name \
    ("harsh flash lighting", "terracotta tile", "oversized tailoring"). This is the most important level: concrete \
    and observable, never evaluative ("beautiful" is not an ingredient).
    For every tag, count = how many of the numbered images clearly show it (at least 1, at most the number of images). \
    Be honest: a tag in most images is the board's signature; don't inflate counts. Give 3–6 feelings, 2–4 references \
    and 6–10 ingredients, strongest first. Tags are 1–4 words, lowercase unless a proper noun, no duplicates across levels. \
    When one of the person's existing words genuinely fits, reuse its exact wording so their collections can be compared.
    about: 2–3 plain sentences on what the board is about and what ties it together, addressed to the person ("Your board…").
    domain: one plural noun for what the board holds (visuals, rooms, outfits, reds, songs, recipes, things).
    verb: the sense that fits the domain. symbol: the icon that fits best.
    statement: one sentence they could say out loud, shaped "I like [domain] that [verb] [feeling or vivid metaphor] — \
    [3–5 signature ingredients]." Under 28 words, no quotation marks.
    """

    private static let schema: [String: Any] = {
        let count = JSONSchema.object([("name", JSONSchema.string()), ("count", ["type": "integer"])])
        return JSONSchema.object([
            ("about", JSONSchema.string()),
            ("domain", JSONSchema.string()),
            ("verb", JSONSchema.stringEnum(verbs)),
            ("symbol", JSONSchema.stringEnum(symbols)),
            ("feelings", JSONSchema.array(count)),
            ("references", JSONSchema.array(count)),
            ("ingredients", JSONSchema.array(count)),
            ("statement", JSONSchema.string()),
        ])
    }()

    /// - Parameters:
    ///   - pinTexts: titles/descriptions of every pin read from the board.
    ///   - images: the sampled pin images (JPEG, already downscaled), in order.
    ///   - totalPins: pins on the board, for context.
    ///   - vocabulary: the person's most-used tags per level, so wording lines up across collections.
    static func analyze(boardName: String, boardDescription: String?, totalPins: Int, pinTexts: [String],
                        images: [Data], vocabulary: [TagLevel: [String]], client: ClaudeClient) async throws -> BoardSummary {
        var lines = ["Board: \(boardName)"]
        if let boardDescription, !boardDescription.isEmpty { lines.append("Board description: \(boardDescription)") }
        lines.append("Pins on the board: \(totalPins). Images attached: \(images.count) (numbered 1–\(images.count) in order).")

        var budget = 12_000
        var texts: [String] = []
        for text in pinTexts {
            let clipped = String(text.prefix(200))
            guard budget - clipped.count > 0 else { break }
            budget -= clipped.count
            texts.append("- \(clipped)")
        }
        if !texts.isEmpty { lines.append("Pin titles and descriptions:\n" + texts.joined(separator: "\n")) }

        for level in TagLevel.allCases {
            if let words = vocabulary[level], !words.isEmpty {
                lines.append("Their existing \(level.pluralTitle.lowercased()): \(words.prefix(25).joined(separator: ", "))")
            }
        }
        lines.append("Summarize the board.")

        let inputs = images.map { ClaudeClient.ImageInput(data: $0) }
        let output = try await client.structured(Output.self, system: system, prompt: lines.joined(separator: "\n\n"),
                                                 images: inputs, schema: schema, effort: .medium, maxTokens: 8_000, timeout: 180)

        // Without images (rare: pins with no media), counts are over the pin texts instead.
        let analyzed = images.isEmpty ? max(texts.count, 1) : images.count
        func counts(_ list: [Output.Count]) -> [NamedCount] {
            list.map { NamedCount(name: $0.name, count: min(max($0.count, 1), analyzed)) }
        }
        let domain = TagText.clean(output.domain).lowercased()
        return BoardSummary(
            about: output.about.trimmingCharacters(in: .whitespacesAndNewlines),
            domain: domain.isEmpty ? "things" : domain,
            verb: verbs.contains(output.verb) ? output.verb : "feel",
            statement: output.statement
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"“”")),
            symbol: symbols.contains(output.symbol) ? output.symbol : "square.stack",
            profile: ImportedProfile(
                analyzedItems: analyzed,
                totalItems: totalPins,
                feelings: counts(output.feelings),
                references: counts(output.references),
                ingredients: counts(output.ingredients)
            )
        )
    }
}
