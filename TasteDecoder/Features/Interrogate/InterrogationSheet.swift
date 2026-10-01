import SwiftData
import SwiftUI

/// Walks one or more saves up the ladder: why → feeling → reference → ingredients.
struct InterrogationSheet: View {
    let queue: InterrogationQueue

    @Environment(\.dismiss) private var dismiss
    @Namespace private var learnNamespace
    @State private var index = 0
    @State private var finishedTick = 0

    var body: some View {
        NavigationStack {
            Group {
                if queue.items.indices.contains(index) {
                    InterrogationView(item: queue.items[index], position: index + 1, total: queue.items.count,
                                      onDone: advance, onClose: { dismiss() })
                        .id(queue.items[index].id)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)))
                }
            }
            .tasteDestinations(learnNamespace)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .sensoryFeedback(.success, trigger: finishedTick)
    }

    private func advance() {
        finishedTick += 1
        if index + 1 < queue.items.count {
            withAnimation(Theme.spring) { index += 1 }
        } else {
            dismiss()
        }
    }
}

struct InterrogationView: View {
    @Bindable var item: SaveItem
    let position: Int
    let total: Int
    let onDone: () -> Void
    let onClose: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Query(filter: #Predicate<TagEntry> { $0.statusRaw == "confirmed" }) private var confirmedTags: [TagEntry]
    @Query(sort: \TasteCollection.sortIndex) private var collections: [TasteCollection]

    @State private var level: TagLevel = .feeling
    @State private var draft = ""
    @State private var suggesting = false
    @State private var suggestionError: String?
    @State private var confirmTick = 0
    @State private var editing: TagEntry?
    @State private var editText = ""
    @FocusState private var draftFocused: Bool
    @Namespace private var chipNamespace

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                whySection
                ladder
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) { bottomBar }
        .navigationTitle(total > 1 ? "Decode \(position) of \(total)" : "Decode")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", action: onClose)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await suggest() }
                } label: {
                    Label("Suggest", systemImage: "sparkles")
                }
                .disabled(suggesting)
            }
        }
        .task { await suggestIfNeeded() }
        .sensoryFeedback(.selection, trigger: confirmTick)
        .alert("Edit tag", isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            TextField("Tag", text: $editText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Save") { commitEdit() }
            Button("Cancel", role: .cancel) { editing = nil }
        } message: {
            Text("Editing a suggestion also keeps it.")
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Group {
                if item.imageFileName != nil || item.artStyle != nil {
                    ItemVisual(item: item, maxPixel: 1200)
                        .frame(maxWidth: .infinity)
                        .frame(height: 300)
                } else {
                    TextTile(item: item)
                        .frame(maxWidth: .infinity)
                        .frame(height: 160)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))

            HStack {
                if let title = item.title, !title.isEmpty {
                    Text(title)
                        .font(.headline)
                        .lineLimit(2)
                } else if let host = item.url?.host() {
                    Label(host, systemImage: "link")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Menu {
                    Button {
                        item.collection = nil
                    } label: {
                        Label("Inbox only", systemImage: "tray")
                    }
                    ForEach(collections) { collection in
                        Button {
                            item.collection = collection
                        } label: {
                            Label(collection.name, systemImage: item.collection == collection ? "checkmark" : collection.symbol)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: item.collection?.symbol ?? "tray")
                        Text(item.collection?.name ?? "Inbox")
                        Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.bold))
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Theme.surface, in: Capsule())
                }
            }
        }
    }

    // MARK: Why

    private var whySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Why did you save this?")
                .font(.title2.weight(.bold))
            TextField("First instinct — what do you like or dislike?", text: Binding(
                get: { item.why ?? "" },
                set: { item.why = $0.isEmpty ? nil : $0 }
            ), axis: .vertical)
            .lineLimit(1...4)
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    // MARK: Ladder

    private var ladder: some View {
        VStack(alignment: .leading, spacing: 18) {
            Picker("Level", selection: $level.animation(Theme.spring)) {
                ForEach(TagLevel.allCases) { level in
                    Text(level.title).tag(level)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 4) {
                Text(level.question)
                    .font(.title3.weight(.semibold))
                Text(level.hint)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .id(level)
            .transition(.opacity)

            let confirmed = item.confirmedTags(level)
            if !confirmed.isEmpty {
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(confirmed) { tag in
                        LearnChip(name: tag.name, context: "decode-\(item.id.uuidString)", style: .confirmed)
                            .contextMenu {
                                Button {
                                    startEdit(tag)
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    remove(tag)
                                } label: {
                                    Label("Remove", systemImage: "minus.circle")
                                }
                            }
                            .matchedGeometryEffect(id: tag.id, in: chipNamespace)
                            .transition(.scale(scale: 0.85).combined(with: .opacity))
                    }
                }
            }

            addField
            suggestionsBlock
            pantryBlock
        }
    }

    private var addField: some View {
        HStack(spacing: 8) {
            Image(systemName: level.symbol)
                .foregroundStyle(.secondary)
            TextField("Add a \(level.noun)", text: $draft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($draftFocused)
                .onSubmit { add(draft) }
            Button {
                add(draft)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
            }
            .disabled(draft.nilIfBlank == nil)
            .accessibilityLabel("Add \(level.noun)")
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(Theme.surface, in: Capsule())
    }

    @ViewBuilder
    private var suggestionsBlock: some View {
        let suggestions = item.suggestedTags(level)
        if !suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Suggested — tap to keep", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Keep all") {
                        withAnimation(Theme.spring) {
                            suggestions.forEach { $0.status = .confirmed }
                            confirmTick += 1
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                }
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(suggestions) { tag in
                        SuggestionChip(name: tag.name) {
                            confirm(tag)
                        } onReject: {
                            reject(tag)
                        }
                        .contextMenu {
                            Button {
                                confirm(tag)
                            } label: {
                                Label("Keep", systemImage: "checkmark")
                            }
                            Button {
                                startEdit(tag)
                            } label: {
                                Label("Edit and keep", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                reject(tag)
                            } label: {
                                Label("Reject", systemImage: "xmark")
                            }
                        }
                        .matchedGeometryEffect(id: tag.id, in: chipNamespace)
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                    }
                }
            }
        } else if suggesting {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .symbolEffect(.pulse)
                    .foregroundStyle(Theme.accent)
                Text("Looking closely…")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .transition(.opacity)
        } else if let suggestionError {
            Label(suggestionError, systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else if !settings.hasAPIKey {
            Label("Add a Claude API key in Settings to get suggestions. Your own words always work.", systemImage: "key")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var pantryBlock: some View {
        let picks = pantryPicks
        if !picks.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label(draft.nilIfBlank == nil ? "From your pantry" : "Matches in your pantry", systemImage: "books.vertical")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(picks, id: \.self) { name in
                        Button {
                            add(name)
                        } label: {
                            TagChip(name: name, style: .muted, symbol: "plus")
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            if let next = level.next {
                Button("Done") { finish() }
                    .buttonStyle(SecondaryButtonStyle())
                Button {
                    withAnimation(Theme.spring) { level = next }
                } label: {
                    Label("Next: \(next.title)", systemImage: "arrow.right")
                        .labelStyle(TrailingIconLabelStyle())
                }
                .buttonStyle(PrimaryButtonStyle())
            } else {
                Button {
                    finish()
                } label: {
                    Text(position < total ? "Done · next save" : "Done")
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.bar)
    }

    // MARK: Pantry picks

    /// Your most-used tags at this level (filtered by what you're typing), not already on this save.
    private var pantryPicks: [String] {
        let onItem = Set(item.tags.filter { $0.level == level && $0.status != .rejected }.map(\.key))
        let needle = TagText.key(draft)
        var counts: [String: (name: String, count: Int)] = [:]
        for tag in confirmedTags where tag.level == level && !onItem.contains(tag.key) {
            if !needle.isEmpty, !tag.key.contains(needle) { continue }
            counts[tag.key, default: (tag.name, 0)].count += 1
        }
        return counts.values
            .sorted { $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count }
            .prefix(12)
            .map(\.name)
    }

    // MARK: Actions

    private func add(_ name: String) {
        guard name.nilIfBlank != nil else { return }
        withAnimation(Theme.spring) {
            context.addTag(name, level: level, to: item)
            draft = ""
            confirmTick += 1
        }
    }

    private func confirm(_ tag: TagEntry) {
        withAnimation(Theme.spring) {
            tag.status = .confirmed
            confirmTick += 1
        }
    }

    private func reject(_ tag: TagEntry) {
        withAnimation(Theme.spring) { tag.status = .rejected }
    }

    private func remove(_ tag: TagEntry) {
        withAnimation(Theme.spring) {
            if tag.source == .ai {
                tag.status = .rejected // Remember it so it isn't suggested again.
            } else {
                context.delete(tag)
            }
        }
    }

    private func startEdit(_ tag: TagEntry) {
        editText = tag.name
        editing = tag
    }

    private func commitEdit() {
        guard let tag = editing, editText.nilIfBlank != nil else { editing = nil; return }
        let newKey = TagText.key(editText)
        withAnimation(Theme.spring) {
            if let duplicate = item.tags.first(where: { $0 !== tag && $0.key == newKey && $0.level == tag.level }) {
                duplicate.status = .confirmed
                context.delete(tag)
            } else {
                tag.rename(editText)
                tag.status = .confirmed
            }
            confirmTick += 1
        }
        editing = nil
    }

    private func finish() {
        if item.decodedAt == nil { item.decodedAt = Date() }
        try? context.save()
        onDone()
    }

    // MARK: AI suggestions

    private func suggestIfNeeded() async {
        guard settings.hasAPIKey, !item.isDecoded, !item.tags.contains(where: { $0.source == .ai }) else { return }
        await suggest()
    }

    private func suggest() async {
        let client: ClaudeClient
        do {
            client = try settings.client()
        } catch {
            suggestionError = error.localizedDescription
            return
        }
        let request = await makeContext()
        guard request.hasSomethingToLookAt else {
            suggestionError = "Write a few words about why you saved it, then tap Suggest."
            return
        }
        withAnimation(Theme.spring) {
            suggesting = true
            suggestionError = nil
        }
        do {
            let result = try await TagSuggester.suggest(request, client: client)
            withAnimation(Theme.spring) {
                apply(result)
                suggesting = false
            }
        } catch {
            withAnimation(Theme.spring) {
                suggestionError = error.localizedDescription
                suggesting = false
            }
        }
    }

    private func makeContext() async -> SuggestionContext {
        var request = SuggestionContext()
        if let fileName = item.imageFileName {
            request.imageJPEG = await Task.detached(priority: .userInitiated) {
                ImageStore.jpegForUpload(named: fileName)
            }.value
        }
        request.title = item.title
        request.note = item.note
        request.urlString = item.urlString
        request.why = item.why
        request.collectionName = item.collection?.name
        request.domain = item.collection?.domain

        var vocabulary: [TagLevel: [String: Int]] = [:]
        for tag in confirmedTags {
            vocabulary[tag.level, default: [:]][tag.name, default: 0] += 1
        }
        for level in TagLevel.allCases {
            let ranked = (vocabulary[level] ?? [:]).sorted { $0.value > $1.value }.prefix(25).map(\.key)
            request.vocabulary[level] = Array(ranked)
        }
        request.existing = item.tags.map(\.name)
        return request
    }

    /// Adds new suggestions as `suggested` (never confirmed) and drops stale unreviewed ones.
    private func apply(_ result: TagSuggestions) {
        var incoming = Set<String>()
        for level in TagLevel.allCases {
            for name in result.names(for: level) { incoming.insert("\(level.rawValue):\(TagText.key(name))") }
        }
        for tag in item.tags where tag.status == .suggested && !incoming.contains("\(tag.levelRaw):\(tag.key)") {
            context.delete(tag)
        }
        for level in TagLevel.allCases {
            for name in result.names(for: level).prefix(6) {
                context.addTag(name, level: level, to: item, status: .suggested, source: .ai)
            }
        }
    }
}

/// A dashed suggestion: tap the name to keep it, the × to reject it.
private struct SuggestionChip: View {
    let name: String
    let onConfirm: () -> Void
    let onReject: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onConfirm) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.accent)
                    Text(name)
                        .lineLimit(1)
                }
                .padding(.leading, 12)
                .padding(.trailing, 6)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("Keep \(name)")

            Button(action: onReject) {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
                    .padding(.trailing, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Reject \(name)")
        }
        .buttonStyle(.plain)
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.primary)
        .background(
            Capsule().strokeBorder(Theme.accent.opacity(0.8), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
        )
    }
}

struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.title
            configuration.icon
        }
    }
}
