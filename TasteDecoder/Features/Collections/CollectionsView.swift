import SwiftData
import SwiftUI

struct CollectionsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \TasteCollection.sortIndex) private var collections: [TasteCollection]
    // Observed so cards refresh as saves and tags change.
    @Query private var allItems: [SaveItem]
    @Query(filter: #Predicate<TagEntry> { $0.statusRaw == "confirmed" }) private var confirmedTags: [TagEntry]

    @Namespace private var learnNamespace
    @State private var path = NavigationPath()
    @State private var editorTarget: CollectionEditorTarget?
    @State private var pendingDelete: TasteCollection?

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(collections) { collection in
                    ZStack {
                        NavigationLink(value: collection) { EmptyView() }
                            .opacity(0)
                        CollectionCard(collection: collection, items: items(in: collection))
                    }
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .swipeActions(edge: .leading) {
                        Button {
                            path.append(CompareRoute(firstID: collection.id, secondID: nil))
                        } label: {
                            Label("Compare", systemImage: "square.split.2x1")
                        }
                        .tint(Theme.accent)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            pendingDelete = collection
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            editorTarget = .edit(collection)
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.gray)
                    }
                    .contextMenu {
                        Button {
                            path.append(DistillRoute(collection: collection))
                        } label: {
                            Label("Distill taste", systemImage: "sparkles")
                        }
                        Button {
                            path.append(CompareRoute(firstID: collection.id, secondID: nil))
                        } label: {
                            Label("Compare with…", systemImage: "square.split.2x1")
                        }
                        Button {
                            editorTarget = .edit(collection)
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Divider()
                        Button(role: .destructive) {
                            pendingDelete = collection
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Collections")
            .overlay {
                if collections.isEmpty {
                    ContentUnavailableView {
                        Label("No collections yet", systemImage: "square.stack")
                    } description: {
                        Text("Name one after a feeling, a reference or an ingredient — like “Uncomfy”.")
                    } actions: {
                        Button("New collection") { editorTarget = .new }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        path.append(CompareRoute())
                    } label: {
                        Label("Compare", systemImage: "square.split.2x1")
                    }
                    .disabled(collections.count < 2)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editorTarget = .new
                    } label: {
                        Label("New collection", systemImage: "plus")
                    }
                }
            }
            .tasteDestinations(learnNamespace)
        }
        .sheet(item: $editorTarget) { target in
            CollectionEditor(target: target, nextSortIndex: (collections.map(\.sortIndex).max() ?? -1) + 1)
        }
        .confirmationDialog("Delete “\(pendingDelete?.name ?? "")”?", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
        ), titleVisibility: .visible) {
            Button("Delete collection", role: .destructive) {
                if let collection = pendingDelete {
                    withAnimation(Theme.spring) { context.delete(collection) }
                    try? context.save()
                }
                pendingDelete = nil
            }
        } message: {
            Text("Its saves stay in your inbox with their tags.")
        }
        .onChange(of: collections.map(\.name)) { _, _ in
            ShareImporter.mirrorCollections(collections)
        }
        .onAppear { ShareImporter.mirrorCollections(collections) }
    }

    private func items(in collection: TasteCollection) -> [SaveItem] {
        allItems.filter { $0.collection == collection }.sorted { $0.createdAt > $1.createdAt }
    }
}

// MARK: - Card

private struct CollectionCard: View {
    let collection: TasteCollection
    let items: [SaveItem]

    var body: some View {
        let distillation = Distiller.distill(items.map(\.snapshot))
        let pending = items.filter { !$0.isDecoded }.count

        VStack(alignment: .leading, spacing: 14) {
            Group {
                if items.isEmpty {
                    ZStack {
                        Theme.surface
                        Image(systemName: collection.symbol)
                            .font(.largeTitle)
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    Mosaic(items: items)
                }
            }
            .frame(height: 190)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(collection.name)
                        .font(.title3.weight(.bold))
                    Text(subtitle(pending: pending))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: collection.symbol)
                    .foregroundStyle(.secondary)
            }

            if !distillation.signatureIngredients.isEmpty {
                Text(distillation.signatureIngredients.prefix(3).map(\.name).joined(separator: " · "))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.accent)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
    }

    private func subtitle(pending: Int) -> String {
        var parts = ["\(items.count) \(items.count == 1 ? "save" : "saves")"]
        if pending > 0 { parts.append("\(pending) to decode") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Editor

enum CollectionEditorTarget: Identifiable {
    case new
    case edit(TasteCollection)

    var id: String {
        switch self {
        case .new: "new"
        case let .edit(collection): collection.id.uuidString
        }
    }
}

struct CollectionEditor: View {
    let target: CollectionEditorTarget
    var nextSortIndex: Int = 0

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var domain = ""
    @State private var verb = "feel"
    @State private var symbol = "square.stack"

    private static let verbs = ["feel", "look", "sound", "taste", "read"]
    private static let symbols = ["square.stack", "eye", "camera", "paintpalette", "wineglass", "fork.knife", "sofa",
                                  "music.note", "film", "book", "tshirt", "leaf", "building.2", "sparkles"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                } header: {
                    Text("Name")
                } footer: {
                    Text("Name it after a feeling (“Uncomfy”), a reference, or an ingredient.")
                }

                Section {
                    TextField("visuals, reds, rooms, songs…", text: $domain)
                        .textInputAutocapitalization(.never)
                    Picker("They", selection: $verb) {
                        ForEach(Self.verbs, id: \.self) { Text($0).tag($0) }
                    }
                } header: {
                    Text("What's in it")
                } footer: {
                    Text("Used in your taste statement: “I like \(domain.nilIfBlank ?? "things") that \(verb) …”")
                }

                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
                        ForEach(Self.symbols, id: \.self) { candidate in
                            Button {
                                symbol = candidate
                            } label: {
                                Image(systemName: candidate)
                                    .font(.body.weight(.medium))
                                    .frame(width: 40, height: 40)
                                    .foregroundStyle(symbol == candidate ? Theme.onAccent : .primary)
                                    .background(symbol == candidate ? Theme.accent : Theme.raised, in: Circle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(isNew ? "New collection" : "Edit collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Create" : "Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(name.nilIfBlank == nil)
                }
            }
            .onAppear(perform: load)
        }
        .presentationDetents([.large])
    }

    private var isNew: Bool {
        if case .new = target { return true }
        return false
    }

    private func load() {
        guard case let .edit(collection) = target else { return }
        name = collection.name
        domain = collection.domain
        verb = collection.verb
        symbol = collection.symbol
    }

    private func save() {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanDomain = domain.nilIfBlank?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "things"
        switch target {
        case .new:
            let collection = TasteCollection(name: cleanName, domain: cleanDomain, verb: verb, symbol: symbol, sortIndex: nextSortIndex)
            context.insert(collection)
        case let .edit(collection):
            collection.name = cleanName
            collection.domain = cleanDomain
            collection.verb = verb
            collection.symbol = symbol
        }
        try? context.save()
        dismiss()
    }
}
