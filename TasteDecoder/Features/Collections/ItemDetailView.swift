import SwiftData
import SwiftUI

struct ItemDetailView: View {
    @Bindable var item: SaveItem

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TasteCollection.sortIndex) private var collections: [TasteCollection]

    @State private var queue: InterrogationQueue?
    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                visual

                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.displayTitle)
                            .font(.title2.weight(.bold))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(meta)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if let url = item.url {
                        Link(destination: url) {
                            Label(url.host()?.replacingOccurrences(of: "www.", with: "") ?? url.absoluteString, systemImage: "safari")
                                .font(.subheadline.weight(.semibold))
                        }
                    }

                    if let note = item.note, !note.isEmpty, item.title != nil || item.kind != .note {
                        Text(note)
                            .font(.system(.body, design: .serif))
                    }

                    if let why = item.why, !why.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Eyebrow(text: "Why I saved it")
                            Text("“\(why)”")
                                .font(.system(.title3, design: .serif))
                                .italic()
                        }
                    }

                    ForEach(TagLevel.allCases) { level in
                        let tags = item.confirmedTags(level)
                        if !tags.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Label(level.pluralTitle, systemImage: level.symbol)
                                    .font(.headline)
                                LearnChipCloud(names: tags.map(\.name), context: "item-\(level.rawValue)",
                                               style: level == .ingredient ? .confirmed : .neutral)
                            }
                        }
                    }

                    Button {
                        queue = InterrogationQueue(items: [item])
                    } label: {
                        Label(item.isDecoded ? "Decode again" : "Decode this save", systemImage: "sparkle.magnifyingglass")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, 4)
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 32)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    MoveToCollectionMenu(item: item, collections: collections)
                    Divider()
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(item: $queue) { queue in
            InterrogationSheet(queue: queue)
        }
        .confirmationDialog("Delete this save?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: deleteAndDismiss)
        } message: {
            Text("Its tags leave your pantry counts too.")
        }
    }

    @ViewBuilder
    private var visual: some View {
        if item.imageFileName != nil || item.artStyle != nil {
            Color.clear
                .aspectRatio(4 / 5, contentMode: .fit)
                .overlay { ItemVisual(item: item, maxPixel: 2000) }
                .clipped()
        } else {
            TextTile(item: item)
                .frame(height: 220)
        }
    }

    private var meta: String {
        let date = item.createdAt.formatted(date: .abbreviated, time: .omitted)
        if let collection = item.collection { return "\(collection.name) · \(date)" }
        return "Inbox · \(date)"
    }

    /// Pop first, then delete, so the screen never renders a deleted model.
    private func deleteAndDismiss() {
        let target = item
        let modelContext = context
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            if let fileName = target.imageFileName { ImageStore.delete(named: fileName) }
            modelContext.delete(target)
            try? modelContext.save()
        }
    }
}
