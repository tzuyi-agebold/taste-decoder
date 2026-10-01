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

    private static let schema = Schema.object([
        ("feelings", Schema.array(Schema.string())),
        ("references", Schema.array(Schema.string())),
        ("ingredients", Schema.array(Schema.string())),
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

    private static let schema = Schema.object([("statement", Schema.string())])

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
        let kinds = Schema.stringEnum(LearnKind.allCases.map(\.rawValue))
        return Schema.object([
            ("title", Schema.string()),
            ("kind", kinds),
            ("summary", Schema.string()),
            ("era", Schema.string()),
            ("characteristics", Schema.array(Schema.string())),
            ("examples", Schema.array(Schema.object([("title", Schema.string()), ("detail", Schema.string())]))),
            ("encounter", Schema.string()),
            ("why_it_matters", Schema.string()),
            ("related", Schema.array(Schema.object([("name", Schema.string()), ("kind", kinds)]))),
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
