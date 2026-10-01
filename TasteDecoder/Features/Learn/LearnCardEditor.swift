import SwiftUI

/// Every Learn card is editable: your glossary, your words.
struct LearnCardEditor: View {
    let card: LearnCardContent
    let onSave: (LearnCardContent) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var kind: LearnKind = .term
    @State private var summary = ""
    @State private var era = ""
    @State private var characteristics = ""
    @State private var examples = ""
    @State private var encounter = ""
    @State private var whyItMatters = ""
    @State private var related = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Kind") {
                    Picker("Kind", selection: $kind) {
                        ForEach(LearnKind.allCases) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section(kind.summaryHeading) {
                    TextField("Summary", text: $summary, axis: .vertical)
                        .lineLimit(2...6)
                }
                Section("Era or movement") {
                    TextField("Optional", text: $era)
                }
                Section {
                    TextEditor(text: $characteristics)
                        .frame(minHeight: 110)
                } header: {
                    Text(kind.characteristicsHeading)
                } footer: {
                    Text("One per line.")
                }
                Section {
                    TextEditor(text: $examples)
                        .frame(minHeight: 110)
                } header: {
                    Text(kind.examplesHeading)
                } footer: {
                    Text("One per line: Title — short detail.")
                }
                Section("In the wild") {
                    TextField("Where you'd encounter it", text: $encounter, axis: .vertical)
                        .lineLimit(1...4)
                }
                Section("Why it matters") {
                    TextField("Why it matters to your taste", text: $whyItMatters, axis: .vertical)
                        .lineLimit(1...4)
                }
                Section {
                    TextEditor(text: $related)
                        .frame(minHeight: 90)
                } header: {
                    Text("Explore next")
                } footer: {
                    Text("One per line. Each becomes a tappable card.")
                }
            }
            .navigationTitle(card.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(edited)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(summary.nilIfBlank == nil)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        kind = card.kind
        summary = card.summary
        era = card.era
        characteristics = card.characteristics.joined(separator: "\n")
        examples = card.examples.map { $0.detail.isEmpty ? $0.title : "\($0.title) — \($0.detail)" }.joined(separator: "\n")
        encounter = card.encounter
        whyItMatters = card.whyItMatters
        related = card.related.map(\.name).joined(separator: "\n")
    }

    private var edited: LearnCardContent {
        func lines(_ text: String) -> [String] {
            text.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        let existingKinds = Dictionary(card.related.map { (TagText.key($0.name), $0.kind) }, uniquingKeysWith: { first, _ in first })
        return LearnCardContent(
            title: card.title,
            kind: kind,
            aliases: card.aliases,
            summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
            era: era.trimmingCharacters(in: .whitespacesAndNewlines),
            characteristics: lines(characteristics),
            examples: lines(examples).map { line in
                let parts = line.components(separatedBy: " — ")
                return LearnExample(title: parts[0], detail: parts.dropFirst().joined(separator: " — "))
            },
            encounter: encounter.trimmingCharacters(in: .whitespacesAndNewlines),
            whyItMatters: whyItMatters.trimmingCharacters(in: .whitespacesAndNewlines),
            related: lines(related).map { LearnLink(name: $0, kind: existingKinds[TagText.key($0)] ?? .term) }
        )
    }
}
