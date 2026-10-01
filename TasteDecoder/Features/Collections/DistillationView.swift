import SwiftData
import SwiftUI

/// The hero screen: recurring ingredients count up, then the taste statement lands.
struct DistillationView: View {
    let collection: TasteCollection

    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var allItems: [SaveItem]
    @Query(filter: #Predicate<TagEntry> { $0.statusRaw == "confirmed" }) private var confirmedTags: [TagEntry]

    @State private var revealed = 0
    @State private var statementShown = false
    @State private var hasRevealed = false
    @State private var showAllIngredients = false
    @State private var polishing = false
    @State private var polishError: String?
    @State private var polishedTick = 0
    @State private var showExport = false
    @State private var editingStatement = false
    @State private var statementDraft = ""

    private static let collapsedRows = 5

    var body: some View {
        let distillation = Distiller.distill(allItems.filter { $0.collection == collection }.map(\.snapshot))
        let rows = showAllIngredients ? distillation.ingredients : Array(distillation.ingredients.prefix(Self.collapsedRows))

        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                header(distillation)
                if distillation.hasContent {
                    ingredientsSection(distillation, rows: rows)
                    statementCard(distillation)
                    clusters(distillation)
                } else {
                    ContentUnavailableView {
                        Label("Nothing to distill yet", systemImage: "sparkles")
                    } description: {
                        Text("Decode a few saves — feeling, reference, ingredients — and the pattern shows up here.")
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .navigationTitle("Taste profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showExport = true
                } label: {
                    Label("Share taste card", systemImage: "square.and.arrow.up")
                }
                .disabled(!distillation.hasContent)
            }
        }
        .task { await reveal(rowCount: rows.count) }
        .sensoryFeedback(.impact(weight: .medium), trigger: statementShown)
        .sensoryFeedback(.success, trigger: polishedTick)
        .sheet(isPresented: $showExport) {
            ExportSheet(collection: collection)
        }
        .alert("Your statement", isPresented: $editingStatement) {
            TextField("I like…", text: $statementDraft)
            Button("Save") { saveEditedStatement(distillation) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Say it the way you'd say it to a friend: feeling + ingredients.")
        }
    }

    // MARK: Sections

    private func header(_ distillation: Distillation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: "Distilled from \(distillation.decodedItems) of \(distillation.totalItems) saves", color: Theme.accent)
            Text(collection.name)
                .font(.largeTitle.weight(.bold))
            if let headline = TasteStatement.headline(distillation) {
                Text(headline)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func ingredientsSection(_ distillation: Distillation, rows: [TagCount]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "What keeps showing up",
                         subtitle: distillation.isTentative ? "An early signal. Decode more saves to confirm the pattern." : "Tap any ingredient to learn what's behind it.")
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, count in
                    IngredientBar(count: count, revealed: index < revealed, context: "distill")
                        .transition(.move(edge: .top).combined(with: .opacity))
                    if index < rows.count - 1 {
                        Divider().opacity(0.4)
                    }
                }
            }
            if distillation.ingredients.count > Self.collapsedRows {
                Button {
                    withAnimation(Theme.spring) { showAllIngredients.toggle() }
                } label: {
                    Label(showAllIngredients ? "Show fewer" : "Show all \(distillation.ingredients.count) ingredients",
                          systemImage: showAllIngredients ? "chevron.up" : "chevron.down")
                        .font(.subheadline.weight(.semibold))
                }
                .padding(.top, 4)
            }
        }
    }

    private func statementCard(_ distillation: Distillation) -> some View {
        let statement = collection.currentStatement(for: distillation)
        let formula = TasteStatement.formula(distillation)

        return VStack(alignment: .leading, spacing: 18) {
            Eyebrow(text: "Your taste in \(collection.domain) is")
            Text(statement.text ?? "")
                .font(Theme.statementFont(.title))
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)

            FormulaRow(formula: formula)

            HStack(spacing: 10) {
                Button {
                    Task { await polish(distillation) }
                } label: {
                    Label(polishing ? "Writing…" : "Polish with Claude", systemImage: "sparkles")
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(polishing)

                Button {
                    statementDraft = statement.text ?? ""
                    editingStatement = true
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .buttonStyle(SecondaryButtonStyle())

                Spacer(minLength: 0)

                ShareLink(item: TasteExport.paragraph(collection: collection, distillation: distillation)) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.body.weight(.semibold))
                        .frame(width: 40, height: 40)
                        .background(Theme.raised, in: Circle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Share statement")
            }

            if let polishError {
                Text(polishError)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if !statement.isWritten {
                Text("A first draft from your counts. Polish it, or say it in your own words.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Theme.accent.opacity(statementShown ? 0.45 : 0), lineWidth: 1)
        )
        .opacity(statementShown ? 1 : 0)
        .offset(y: statementShown ? 0 : 28)
        .scaleEffect(statementShown ? 1 : 0.96, anchor: .top)
    }

    private func clusters(_ distillation: Distillation) -> some View {
        VStack(alignment: .leading, spacing: 28) {
            if !distillation.feelings.isEmpty {
                cluster(title: "Feelings", level: .feeling, counts: distillation.feelings)
            }
            if !distillation.references.isEmpty {
                cluster(title: "References", level: .reference, counts: distillation.references)
            }
        }
        .opacity(statementShown ? 1 : 0)
    }

    private func cluster(title: String, level: TagLevel, counts: [TagCount]) -> some View {
        let shown = Array(counts.prefix(10))
        return VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: level.symbol)
                .font(.headline)
            LearnChipCloud(names: shown.map(\.name), context: "distill-\(level.rawValue)",
                           counts: Dictionary(shown.map { ($0.name, "\($0.count)") }, uniquingKeysWith: { first, _ in first }))
        }
    }

    // MARK: Reveal

    private func reveal(rowCount: Int) async {
        guard !hasRevealed else { return }
        hasRevealed = true
        if reduceMotion {
            revealed = 999
            statementShown = true
            return
        }
        try? await Task.sleep(for: .milliseconds(250))
        for index in 0..<rowCount {
            withAnimation(Theme.reveal) { revealed = index + 1 }
            try? await Task.sleep(for: .milliseconds(120))
        }
        try? await Task.sleep(for: .milliseconds(180))
        withAnimation(Theme.reveal) {
            revealed = 999
            statementShown = true
        }
    }

    // MARK: Statement

    private func polish(_ distillation: Distillation) async {
        let client: ClaudeClient
        do {
            client = try settings.client()
        } catch {
            polishError = "Add a Claude API key in Settings to polish statements. The draft works offline."
            return
        }
        polishing = true
        polishError = nil
        do {
            let text = try await TasteStatementWriter.write(collectionName: collection.name, domain: collection.domain,
                                                            verb: collection.verb, distillation: distillation, client: client)
            withAnimation(Theme.spring) {
                collection.statement = text
                collection.statementSignature = distillation.signature
            }
            try? context.save()
            polishedTick += 1
        } catch {
            polishError = error.localizedDescription
        }
        polishing = false
    }

    private func saveEditedStatement(_ distillation: Distillation) {
        guard let text = statementDraft.nilIfBlank else { return }
        collection.statement = text.trimmingCharacters(in: .whitespacesAndNewlines)
        collection.statementSignature = distillation.signature
        try? context.save()
    }
}

// MARK: - Components

/// One recurring ingredient: name, "7 of 10", and a bar that fills on reveal. Tap → Learn card.
struct IngredientBar: View {
    let count: TagCount
    let revealed: Bool
    let context: String

    @Environment(\.learnNamespace) private var namespace

    var body: some View {
        let route = LearnRoute(name: count.name, context: context)
        NavigationLink(value: route) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(count.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 12)
                    Text("\(revealed ? count.count : 0) of \(count.total)")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(revealed ? Theme.accent : .secondary)
                        .contentTransition(.numericText(value: Double(revealed ? count.count : 0)))
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.raised)
                        Capsule()
                            .fill(Theme.accent)
                            .frame(width: revealed ? max(proxy.size.width * count.fraction, 6) : 0)
                    }
                }
                .frame(height: 6)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .zoomSource(id: route.sourceID, in: namespace)
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(count.name), \(count.count) of \(count.total) saves")
    }
}

/// feeling + references + ingredients, each tappable.
struct FormulaRow: View {
    let formula: TasteFormula

    var body: some View {
        FlowLayout(spacing: 6, lineSpacing: 8) {
            if let feeling = formula.feeling {
                LearnChip(name: feeling, context: "formula", symbol: TagLevel.feeling.symbol)
            }
            if formula.feeling != nil, !formula.references.isEmpty {
                plus
            }
            ForEach(formula.references, id: \.self) { reference in
                LearnChip(name: reference, context: "formula", symbol: TagLevel.reference.symbol)
            }
            if (formula.feeling != nil || !formula.references.isEmpty), !formula.ingredients.isEmpty {
                plus
            }
            ForEach(formula.ingredients, id: \.self) { ingredient in
                LearnChip(name: ingredient, context: "formula", style: .confirmed)
            }
        }
    }

    private var plus: some View {
        Text("+")
            .font(.headline)
            .foregroundStyle(.secondary)
            .padding(.vertical, 6)
    }
}
