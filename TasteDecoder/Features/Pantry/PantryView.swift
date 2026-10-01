import SwiftData
import SwiftUI

/// Your personal glossary: every confirmed feeling, reference and ingredient, with counts.
struct PantryView: View {
    @Environment(\.modelContext) private var context
    @Environment(LearnLibrary.self) private var library
    @Query(filter: #Predicate<TagEntry> { $0.statusRaw == "confirmed" }) private var confirmedTags: [TagEntry]
    @Query private var records: [LearnCardRecord]

    @Namespace private var learnNamespace
    @State private var path = NavigationPath()
    @State private var query = ""
    @State private var filter: LevelFilter = .all
    @State private var sort: SortOrder = .mostUsed
    @State private var renaming: PantryEntry?
    @State private var renameText = ""
    @State private var pendingRemoval: PantryEntry?

    enum LevelFilter: String, CaseIterable, Identifiable {
        case all, feeling, reference, ingredient
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: "All"
            case .feeling: "Feelings"
            case .reference: "References"
            case .ingredient: "Ingredients"
            }
        }
        var level: TagLevel? { TagLevel(rawValue: rawValue) }
    }

    enum SortOrder: String, CaseIterable, Identifiable {
        case mostUsed, alphabetical
        var id: String { rawValue }
        var title: String { self == .mostUsed ? "Most used" : "A–Z" }
    }

    private var entries: [PantryEntry] {
        PantryIndex.build(confirmedTags.compactMap { tag in
            guard let item = tag.item else { return nil }
            return TagUsage(name: tag.name, level: tag.level, itemID: item.id, collectionName: item.collection?.name)
        })
    }

    var body: some View {
        let all = entries
        let visible = filtered(all)

        NavigationStack(path: $path) {
            List {
                Section {
                    Picker("Level", selection: $filter.animation(Theme.spring)) {
                        ForEach(LevelFilter.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                } footer: {
                    Text(summary(all))
                }

                Section {
                    ForEach(visible) { entry in
                        NavigationLink(value: LearnRoute(name: entry.name, context: "pantry")) {
                            PantryRow(entry: entry, blurb: blurb(for: entry))
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                pendingRemoval = entry
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                            Button {
                                renameText = entry.name
                                renaming = entry
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            .tint(.gray)
                        }
                        .contextMenu {
                            Button {
                                renameText = entry.name
                                renaming = entry
                            } label: {
                                Label("Rename or merge", systemImage: "pencil")
                            }
                            Button {
                                UIPasteboard.general.string = entry.name
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                            Divider()
                            Button(role: .destructive) {
                                pendingRemoval = entry
                            } label: {
                                Label("Remove from all saves", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Pantry")
            .searchable(text: $query, prompt: "Search your ingredients")
            .overlay {
                if all.isEmpty {
                    ContentUnavailableView {
                        Label("Your pantry is empty", systemImage: "books.vertical")
                    } description: {
                        Text("Every feeling, reference and ingredient you confirm lands here and grows into your glossary.")
                    }
                } else if visible.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Sort", selection: $sort) {
                            ForEach(SortOrder.allCases) { Text($0.title).tag($0) }
                        }
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                    }
                }
            }
            .tasteDestinations(learnNamespace)
        }
        .alert("Rename “\(renaming?.name ?? "")”", isPresented: Binding(
            get: { renaming != nil }, set: { if !$0 { renaming = nil } }
        )) {
            TextField("New name", text: $renameText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Rename") { commitRename() }
            Button("Cancel", role: .cancel) { renaming = nil }
        } message: {
            Text("Renames it on every save. Use an existing name to merge the two.")
        }
        .confirmationDialog("Remove “\(pendingRemoval?.name ?? "")” from all saves?", isPresented: Binding(
            get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }
        ), titleVisibility: .visible) {
            Button("Remove", role: .destructive) { commitRemoval() }
        }
    }

    // MARK: Helpers

    private func filtered(_ all: [PantryEntry]) -> [PantryEntry] {
        let needle = TagText.key(query)
        let byLevel = all.filter { filter.level == nil || $0.level == filter.level }
        let searched = needle.isEmpty ? byLevel : byLevel.filter { $0.key.contains(needle) }
        switch sort {
        case .mostUsed: return searched
        case .alphabetical: return searched.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    private func summary(_ all: [PantryEntry]) -> String {
        let counts = Dictionary(grouping: all, by: \.level).mapValues(\.count)
        return TagLevel.allCases
            .map { level in "\(counts[level] ?? 0) \((counts[level] ?? 0) == 1 ? level.noun : level.pluralTitle.lowercased())" }
            .joined(separator: " · ")
    }

    private func blurb(for entry: PantryEntry) -> String? {
        let content = records.first(where: { $0.key == entry.key })?.content ?? library.card(for: entry.key)
        return content?.summary
    }

    private func tags(for entry: PantryEntry) -> [TagEntry] {
        confirmedTags.filter { $0.key == entry.key && $0.level == entry.level }
    }

    private func commitRename() {
        guard let entry = renaming, let newName = renameText.nilIfBlank else { renaming = nil; return }
        let newKey = TagText.key(newName)
        withAnimation(Theme.spring) {
            for tag in tags(for: entry) {
                // Merge: if the save already has the new name at this level, drop the duplicate.
                if let item = tag.item,
                   item.tags.contains(where: { $0 !== tag && $0.key == newKey && $0.level == tag.level && $0.status == .confirmed }) {
                    context.delete(tag)
                } else {
                    tag.rename(newName)
                }
            }
        }
        try? context.save()
        renaming = nil
    }

    private func commitRemoval() {
        guard let entry = pendingRemoval else { return }
        withAnimation(Theme.spring) {
            for tag in tags(for: entry) { context.delete(tag) }
        }
        try? context.save()
        pendingRemoval = nil
    }
}

private struct PantryRow: View {
    let entry: PantryEntry
    let blurb: String?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: entry.level.symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(entry.level == .ingredient ? Theme.accent : .secondary)
                .frame(width: 22)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name)
                    .font(.body.weight(.medium))
                if let blurb {
                    Text(blurb)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Text(entry.collectionNames.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text("\(entry.itemCount)")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Theme.raised, in: Capsule())
        }
        .padding(.vertical, 4)
    }
}
