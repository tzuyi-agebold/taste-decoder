import SwiftData
import SwiftUI

struct CollectionDetailView: View {
    @Bindable var collection: TasteCollection

    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Query(sort: \SaveItem.createdAt, order: .reverse) private var allItems: [SaveItem]
    @Query(filter: #Predicate<TagEntry> { $0.statusRaw == "confirmed" }) private var confirmedTags: [TagEntry]
    @Query(sort: \TasteCollection.sortIndex) private var collections: [TasteCollection]

    @State private var capture = CaptureController()
    @State private var queue: InterrogationQueue?
    @State private var showEditor = false
    @State private var showExport = false
    @State private var savedTick = 0
    @State private var importer = PinterestImporter()
    @State private var refreshError: String?

    private var items: [SaveItem] { allItems.filter { $0.collection == collection } }

    var body: some View {
        let saves = items
        let distillation = collection.effectiveDistillation(items: saves)
        let pending = saves.filter { !$0.isDecoded }

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ProfileSummary(collection: collection, distillation: distillation) {
                    queue = InterrogationQueue(items: Array(pending.reversed()))
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 16)

                if let source = collection.source {
                    ImportedSourceCard(collection: collection, source: source, isRefreshing: isRefreshing)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                }

                if !pending.isEmpty, distillation.decodedItems > 0 {
                    PendingBanner(count: pending.count) {
                        queue = InterrogationQueue(items: Array(pending.reversed()))
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }

                if saves.isEmpty, collection.isImported {
                    CoverGrid(names: collection.coverImageNames)
                    Text("Add your own saves with ＋ and they count alongside the board.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                } else if saves.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing saved here yet", systemImage: collection.symbol)
                    } description: {
                        Text("Add photos, links or notes. Decode them, and the pattern shows up above.")
                    } actions: {
                        Button {
                            capture.start(.photos)
                        } label: {
                            Label("Add photos", systemImage: "photo.on.rectangle")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.top, 24)
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.tileSpacing), count: 3),
                              spacing: Theme.tileSpacing) {
                        ForEach(saves) { item in
                            tile(item)
                        }
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .navigationTitle(collection.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Button { capture.start(.camera) } label: { Label("Camera", systemImage: "camera") }
                    Button { capture.start(.photos) } label: { Label("Photos", systemImage: "photo.on.rectangle") }
                    Button { capture.start(.link) } label: { Label("Link", systemImage: "link") }
                    Button { capture.start(.note) } label: { Label("Note", systemImage: "text.quote") }
                } label: {
                    Label("Add", systemImage: "plus")
                }
                Menu {
                    Button { showExport = true } label: { Label("Share taste card", systemImage: "square.and.arrow.up") }
                    Button { showEditor = true } label: { Label("Edit collection", systemImage: "pencil") }
                    if collection.source == .pinterest {
                        Divider()
                        Button {
                            Task { await refresh() }
                        } label: {
                            Label("Refresh from Pinterest", systemImage: "arrow.clockwise")
                        }
                        .disabled(isRefreshing)
                        if let url = collection.sourceURL.flatMap(URL.init(string:)) {
                            Link(destination: url) { Label("Open in Pinterest", systemImage: "safari") }
                        }
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .captureFlows(capture, destination: collection) { savedTick += 1 }
        .sheet(item: $queue) { queue in
            InterrogationSheet(queue: queue)
        }
        .sheet(isPresented: $showEditor) {
            CollectionEditor(target: .edit(collection))
        }
        .sheet(isPresented: $showExport) {
            ExportSheet(collection: collection)
        }
        .sensoryFeedback(.success, trigger: savedTick)
        .alert("Couldn't refresh", isPresented: Binding(get: { refreshError != nil }, set: { if !$0 { refreshError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(refreshError ?? "")
        }
    }

    private var isRefreshing: Bool { importer.isRunning }

    /// Re-reads the board and rewrites the summary in place.
    private func refresh() async {
        guard collection.source == .pinterest, let boardID = collection.sourceID else { return }
        let board = PinterestBoard(id: boardID, name: collection.name, description: nil, pinCount: collection.sourceItemCount,
                                   privacy: "public", coverImageURL: nil, thumbnailURLs: [], url: collection.sourceURL)
        await importer.run([board], context: context, settings: settings)
        if case let .failed(message) = importer.steps[boardID] { refreshError = message }
        importer.reset()
    }

    @ViewBuilder
    private func tile(_ item: SaveItem) -> some View {
        Group {
            if item.isDecoded {
                NavigationLink(value: item) {
                    ItemTile(item: item)
                }
            } else {
                Button {
                    queue = InterrogationQueue(items: [item])
                } label: {
                    ItemTile(item: item)
                        .overlay(alignment: .topTrailing) {
                            Text("Why?")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Theme.onAccent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Theme.accent, in: Capsule())
                                .padding(6)
                        }
                }
            }
        }
        .buttonStyle(PressableStyle())
        .contextMenu {
            Button {
                queue = InterrogationQueue(items: [item])
            } label: {
                Label(item.isDecoded ? "Decode again" : "Decode", systemImage: "sparkle.magnifyingglass")
            }
            MoveToCollectionMenu(item: item, collections: collections)
            Divider()
            Button(role: .destructive) {
                if let fileName = item.imageFileName { ImageStore.delete(named: fileName) }
                withAnimation(Theme.spring) { context.delete(item) }
                try? context.save()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Imported source

/// "About this board": what Claude made of it and where it came from.
private struct ImportedSourceCard: View {
    let collection: TasteCollection
    let source: CollectionSource
    let isRefreshing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                SourceBadge(source: source, size: 22)
                Eyebrow(text: "About this \(source == .pinterest ? "board" : "source")")
                Spacer()
                if isRefreshing {
                    ProgressView()
                }
            }
            if let summary = collection.summary, !summary.isEmpty {
                Text(summary)
                    .font(.system(.body, design: .serif))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(provenance)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .cardBackground()
    }

    private var provenance: String {
        var parts: [String] = []
        if let profile = collection.importedProfile {
            let total = max(collection.sourceItemCount, profile.totalItems)
            parts.append("Read from \(profile.analyzedItems) of \(total) \(source.itemNoun(total))")
        }
        if let date = collection.importedAt {
            parts.append("updated \(date.formatted(.relative(presentation: .named)))")
        }
        return parts.joined(separator: " · ")
    }
}

/// The imported cover images, edge to edge.
private struct CoverGrid: View {
    let names: [String]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.tileSpacing), count: 2),
                  spacing: Theme.tileSpacing) {
            ForEach(names, id: \.self) { name in
                Color.clear
                    .aspectRatio(0.8, contentMode: .fit)
                    .overlay { StoredImage(fileName: name, maxPixel: 700) }
                    .clipped()
            }
        }
    }
}

// MARK: - Summary card

private struct ProfileSummary: View {
    let collection: TasteCollection
    let distillation: Distillation
    let onDecode: () -> Void

    var body: some View {
        let statement = collection.currentStatement(for: distillation)

        VStack(alignment: .leading, spacing: 16) {
            if distillation.decodedItems == 0 {
                Eyebrow(text: "Your taste in \(collection.domain)")
                Text("Decode a few saves and your taste statement appears here.")
                    .font(Theme.statementFont(.title3))
                    .foregroundStyle(.secondary)
                if distillation.totalItems > 0 {
                    Button(action: onDecode) {
                        Label("Decode \(distillation.totalItems) \(distillation.totalItems == 1 ? "save" : "saves")", systemImage: "sparkle.magnifyingglass")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            } else {
                Eyebrow(text: "Your taste in \(collection.domain)")
                Text(statement.text ?? "")
                    .font(Theme.statementFont(.title2))
                    .fixedSize(horizontal: false, vertical: true)

                if !distillation.signatureIngredients.isEmpty {
                    FlowLayout(spacing: 8, lineSpacing: 8) {
                        ForEach(distillation.signatureIngredients.prefix(4)) { count in
                            LearnChip(name: count.name, context: "summary", count: "\(count.count)/\(count.total)")
                        }
                    }
                }

                HStack(spacing: 10) {
                    NavigationLink(value: DistillRoute(collection: collection)) {
                        Label("Distill", systemImage: "sparkles")
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    NavigationLink(value: CompareRoute(firstID: collection.id, secondID: nil)) {
                        Label("Compare", systemImage: "square.split.2x1")
                            .frame(minHeight: 52)
                            .padding(.horizontal, 6)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
        }
        .cardBackground()
    }
}

private struct PendingBanner: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "sparkle.magnifyingglass")
                    .foregroundStyle(Theme.accent)
                Text("\(count) \(count == 1 ? "save is" : "saves are") waiting to be decoded")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Spacer()
                Text("Decode")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }
}
