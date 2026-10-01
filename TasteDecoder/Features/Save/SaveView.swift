import PhotosUI
import SwiftData
import SwiftUI

/// The inbox. Save fast while scrolling; interrogate later.
struct SaveView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SaveItem.createdAt, order: .reverse) private var items: [SaveItem]
    @Query(sort: \TasteCollection.sortIndex) private var collections: [TasteCollection]
    @AppStorage("captureCollectionID") private var captureCollectionID = ""

    @Namespace private var learnNamespace
    @State private var path = NavigationPath()
    @State private var capture = CaptureController()
    @State private var queue: InterrogationQueue?
    @State private var showSettings = false
    @State private var savedTick = 0

    private var pending: [SaveItem] { items.filter { !$0.isDecoded } }
    private var recent: [SaveItem] { Array(items.filter(\.isDecoded).prefix(6)) }

    private var destination: TasteCollection? {
        collections.first { $0.id.uuidString == captureCollectionID }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    CaptureDeck(capture: capture, destination: destination, collections: collections,
                                destinationID: $captureCollectionID) { text in
                        if Capture.addPasted(text, to: destination, context: context) != nil { savedTick += 1 }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                Section {
                    if pending.isEmpty {
                        ContentUnavailableView {
                            Label("Nothing to decode", systemImage: "checkmark.circle")
                        } description: {
                            Text("Save something that catches your eye. Ask why later.")
                        }
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(pending) { item in
                            Button {
                                queue = InterrogationQueue(items: [item])
                            } label: {
                                SaveRow(item: item, showsDecode: true)
                            }
                            .buttonStyle(PressableStyle())
                            .swipeActions(edge: .leading) {
                                Button {
                                    queue = InterrogationQueue(items: [item])
                                } label: {
                                    Label("Decode", systemImage: "sparkle.magnifyingglass")
                                }
                                .tint(Theme.accent)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { delete(item) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .contextMenu { itemMenu(item) }
                        }
                    }
                } header: {
                    HStack {
                        Text("To decode")
                        Spacer()
                        if pending.count > 1 {
                            Button("Decode all \(pending.count)") {
                                queue = InterrogationQueue(items: Array(pending.reversed()))
                            }
                            .font(.subheadline.weight(.semibold))
                            .textCase(nil)
                        }
                    }
                }

                if !recent.isEmpty {
                    Section("Recently decoded") {
                        ForEach(recent) { item in
                            NavigationLink(value: item) {
                                SaveRow(item: item, showsDecode: false)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { delete(item) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .contextMenu { itemMenu(item) }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Save")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .tasteDestinations(learnNamespace)
        }
        .captureFlows(capture, destination: destination) { savedTick += 1 }
        .sheet(item: $queue) { queue in
            InterrogationSheet(queue: queue)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sensoryFeedback(.success, trigger: savedTick)
    }

    @ViewBuilder
    private func itemMenu(_ item: SaveItem) -> some View {
        Button {
            queue = InterrogationQueue(items: [item])
        } label: {
            Label(item.isDecoded ? "Decode again" : "Decode", systemImage: "sparkle.magnifyingglass")
        }
        MoveToCollectionMenu(item: item, collections: collections)
        Divider()
        Button(role: .destructive) { delete(item) } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private func delete(_ item: SaveItem) {
        if let fileName = item.imageFileName { ImageStore.delete(named: fileName) }
        withAnimation(Theme.spring) { context.delete(item) }
        try? context.save()
    }
}

// MARK: - Capture deck

private struct CaptureDeck: View {
    let capture: CaptureController
    let destination: TasteCollection?
    let collections: [TasteCollection]
    @Binding var destinationID: String
    let onPaste: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                CaptureButton(title: "Camera", symbol: "camera") { capture.start(.camera) }
                CaptureButton(title: "Photos", symbol: "photo.on.rectangle") { capture.start(.photos) }
                CaptureButton(title: "Link", symbol: "link") { capture.start(.link) }
                CaptureButton(title: "Note", symbol: "text.quote") { capture.start(.note) }
            }

            HStack(spacing: 12) {
                Menu {
                    Picker("Save to", selection: $destinationID) {
                        Label("Inbox only", systemImage: "tray").tag("")
                        ForEach(collections) { collection in
                            Label(collection.name, systemImage: collection.symbol).tag(collection.id.uuidString)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text("Saving to")
                            .foregroundStyle(.secondary)
                        Text(destination?.name ?? "Inbox")
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }

                Spacer()

                PasteButton(payloadType: String.self) { strings in
                    guard let text = strings.first else { return }
                    Task { @MainActor in onPaste(text) }
                }
                .buttonBorderShape(.capsule)
                .labelStyle(.titleAndIcon)
                .tint(Color(uiColor: .systemGray2))
            }
        }
        .padding(.vertical, 4)
    }
}

private struct CaptureButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(Theme.accent)
                    .frame(height: 24)
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, minHeight: 84)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - Rows

struct SaveRow: View {
    let item: SaveItem
    var showsDecode: Bool

    var body: some View {
        HStack(spacing: 14) {
            ItemTile(item: item, maxPixel: 200)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayTitle)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if showsDecode {
                Text("Why?")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Theme.accent, in: Capsule())
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        let when = item.createdAt.formatted(.relative(presentation: .named))
        if let collection = item.collection { return "\(collection.name) · \(when)" }
        if showsDecode { return "Inbox · \(when)" }
        let count = item.confirmedTags.count
        return "\(count) \(count == 1 ? "tag" : "tags") · \(when)"
    }
}

struct MoveToCollectionMenu: View {
    let item: SaveItem
    let collections: [TasteCollection]

    var body: some View {
        Menu {
            Button {
                item.collection = nil
                try? item.modelContext?.save()
            } label: {
                Label("Inbox only", systemImage: "tray")
            }
            ForEach(collections) { collection in
                Button {
                    item.collection = collection
                    try? item.modelContext?.save()
                } label: {
                    Label(collection.name, systemImage: item.collection == collection ? "checkmark" : collection.symbol)
                }
            }
        } label: {
            Label("Move to…", systemImage: "folder")
        }
    }
}
