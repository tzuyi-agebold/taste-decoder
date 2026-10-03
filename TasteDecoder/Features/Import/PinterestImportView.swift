import AuthenticationServices
import SwiftData
import SwiftUI

/// Connect Pinterest, pick boards, and let Claude turn each one into a collection.
struct PinterestImportView: View {
    /// Called with a freshly imported collection the user wants to open.
    var onOpen: (TasteCollection) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @Environment(AppSettings.self) private var settings
    @Environment(AccountStore.self) private var account
    @Environment(SyncService.self) private var sync
    @Query(filter: #Predicate<TasteCollection> { $0.sourceRaw == "pinterest" }) private var imported: [TasteCollection]

    @Namespace private var learnNamespace
    @State private var phase: Phase = .loading
    @State private var username: String?
    @State private var boards: [PinterestBoard] = []
    @State private var selection: Set<String> = []
    @State private var importing: [PinterestBoard] = []
    @State private var importer = PinterestImporter()
    @State private var isConnecting = false
    @State private var errorMessage: String?
    @State private var finishedTick = 0

    enum Phase: Equatable {
        case loading
        case notConfigured
        case signedOut
        case disconnected
        case boards
        case importing
        case results
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        if phase != .results {
                            Button("Cancel") { dismiss() }
                                .disabled(phase == .importing)
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if phase == .results {
                            Button("Done") { dismiss() }
                                .fontWeight(.semibold)
                        }
                    }
                }
                .tasteDestinations(learnNamespace)
        }
        .interactiveDismissDisabled(phase == .importing)
        .task(id: account.isSignedIn) { await load() }
        .sensoryFeedback(.success, trigger: finishedTick)
        .alert("Pinterest", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var title: String {
        switch phase {
        case .importing: "Reading your boards"
        case .results: importing.count == 1 ? "Your board, decoded" : "Your boards, decoded"
        default: "Import from Pinterest"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .notConfigured:
            ContentUnavailableView {
                Label("Backend not set up", systemImage: "server.rack")
            } description: {
                Text("Pinterest import needs the Taste Decoder backend. Add your Supabase project to Config/Secrets.xcconfig — see the README.")
            }
        case .signedOut:
            ContentUnavailableView {
                Label("Sign in to import", systemImage: "person.crop.circle")
            } description: {
                Text("Sign in with Google so Taste Decoder can connect to Pinterest for you. Your saves sync too.")
            } actions: {
                Button {
                    Task { await account.signInWithGoogle() }
                } label: {
                    if account.isWorking { ProgressView() } else { Text("Sign in with Google") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(account.isWorking)
                if let message = account.errorMessage {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
            }
        case .disconnected:
            connectView
        case .boards:
            boardList
        case .importing:
            progressList
        case .results:
            results
        case let .failed(message):
            ContentUnavailableView {
                Label("Couldn't load your boards", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { Task { await load() } }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: Connect

    private var connectView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SourceBadge(source: .pinterest, size: 56)
                    .padding(.top, 24)
                Text("Bring in your boards")
                    .font(.largeTitle.weight(.bold))
                VStack(alignment: .leading, spacing: 14) {
                    point("square.stack", "Pick the boards you want. Each becomes one collection.")
                    point("sparkles", "Claude looks across up to \(PinterestImporter.sampleSize) pins per board and tells you what it's about, what keeps showing up, and how it feels.")
                    point("lock", "Taste Decoder only reads your boards. It never pins or posts, and you can disconnect any time.")
                }
                Button {
                    Task { await connect() }
                } label: {
                    if isConnecting {
                        ProgressView().tint(Theme.onAccent)
                    } else {
                        Text("Connect Pinterest")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isConnecting)
                .padding(.top, 8)
            }
            .padding(.horizontal, 24)
        }
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).foregroundStyle(Theme.accent)
        }
    }

    // MARK: Boards

    private var boardList: some View {
        List {
            Section {
                ForEach(boards) { board in
                    Button {
                        toggle(board)
                    } label: {
                        BoardRow(board: board, isSelected: selection.contains(board.id),
                                 isImported: importedIDs.contains(board.id))
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                if let username { Text("@\(username)") }
            } footer: {
                Text("Already imported? Picking it again refreshes the collection. Claude reads up to \(PinterestImporter.sampleSize) pins per board.")
            }
        }
        .overlay {
            if boards.isEmpty {
                ContentUnavailableView("No boards yet", systemImage: "square.stack",
                                       description: Text("Boards you create on Pinterest show up here."))
            }
        }
        .refreshable { await load() }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                Button {
                    Task { await runImport() }
                } label: {
                    Text(selection.isEmpty ? "Choose boards to import"
                         : "Import \(selection.count) \(selection.count == 1 ? "board" : "boards")")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(selection.isEmpty)
                Button("Disconnect Pinterest", role: .destructive) {
                    Task { await disconnect() }
                }
                .font(.footnote)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.bar)
        }
    }

    private var importedIDs: Set<String> { Set(imported.compactMap(\.sourceID)) }

    private func toggle(_ board: PinterestBoard) {
        if selection.contains(board.id) { selection.remove(board.id) } else { selection.insert(board.id) }
    }

    // MARK: Progress

    private var progressList: some View {
        List(importing) { board in
            HStack(spacing: 12) {
                BoardThumbnail(url: board.coverImageURL)
                VStack(alignment: .leading, spacing: 3) {
                    Text(board.name).font(.body.weight(.semibold))
                    Text(describe(importer.steps[board.id] ?? .waiting))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                }
                Spacer()
                switch importer.steps[board.id] ?? .waiting {
                case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                case .waiting: Image(systemName: "circle.dotted").foregroundStyle(.tertiary)
                default: ProgressView()
                }
            }
            .padding(.vertical, 4)
            .animation(Theme.spring, value: importer.steps[board.id])
        }
    }

    private func describe(_ step: PinterestImporter.Step) -> String {
        switch step {
        case .waiting: "Waiting…"
        case .reading: "Reading pins…"
        case let .looking(downloaded, total): "Gathering images \(downloaded) of \(total)…"
        case let .analyzing(pins, images): "Looking closely at \(images) of \(pins) pins…"
        case .done: "Done"
        case let .failed(message): message
        }
    }

    // MARK: Results

    private var results: some View {
        ScrollView {
            VStack(spacing: 20) {
                ForEach(importing) { board in
                    switch importer.steps[board.id] ?? .waiting {
                    case let .done(collectionID):
                        if let collection = imported.first(where: { $0.id == collectionID }) {
                            BoardSummaryCard(collection: collection) {
                                onOpen(collection)
                            }
                        }
                    case let .failed(message):
                        Label("\(board.name): \(message)", systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .cardBackground()
                    default:
                        EmptyView()
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: Actions

    private func load() async {
        guard Backend.isConfigured else { phase = .notConfigured; return }
        guard account.isSignedIn else { phase = .signedOut; return }
        if phase != .boards { phase = .loading }
        do {
            let status = try await PinterestAPI.status()
            guard status.connected else { phase = .disconnected; return }
            let list = try await PinterestAPI.boards()
            username = list.username ?? status.username
            boards = list.boards
            selection.formIntersection(Set(boards.map(\.id)))
            phase = .boards
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func connect() async {
        isConnecting = true
        defer { isConnecting = false }
        do {
            let url = try await PinterestAPI.authorizeURL()
            let callback = try await webAuthenticationSession.authenticate(using: url, callbackURLScheme: "tastedecoder")
            switch PinterestAPI.callbackResult(callback) {
            case .success: await load()
            case let .failure(error): errorMessage = error.localizedDescription
            }
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            // Closed the Pinterest sheet.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func disconnect() async {
        do {
            try await PinterestAPI.disconnect()
            boards = []
            selection = []
            phase = .disconnected
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func runImport() async {
        guard settings.canUseClaude else {
            errorMessage = ClaudeClient.ClaudeError.missingKey.localizedDescription
            return
        }
        importing = boards.filter { selection.contains($0.id) }
        importer.reset()
        withAnimation(Theme.spring) { phase = .importing }
        await importer.run(importing, context: context, settings: settings)
        finishedTick += 1
        withAnimation(Theme.spring) { phase = .results }
        await sync.sync(context)
    }
}

// MARK: - Pieces

private struct BoardThumbnail: View {
    let url: String?

    var body: some View {
        AsyncImage(url: url.flatMap(URL.init(string:))) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            ZStack {
                Theme.raised
                Image(systemName: "square.stack").foregroundStyle(.tertiary)
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct BoardRow: View {
    let board: PinterestBoard
    let isSelected: Bool
    let isImported: Bool

    var body: some View {
        HStack(spacing: 12) {
            BoardThumbnail(url: board.coverImageURL ?? board.thumbnailURLs.first)
            VStack(alignment: .leading, spacing: 3) {
                Text(board.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                HStack(spacing: 6) {
                    Text("\(board.pinCount) \(board.pinCount == 1 ? "pin" : "pins")")
                    if board.isSecret { Label("Secret", systemImage: "lock.fill").labelStyle(.titleAndIcon) }
                    if isImported { Text("· Imported").foregroundStyle(Theme.accent) }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? Theme.accent : Color.secondary)
                .contentTransition(.symbolEffect(.replace))
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The summary of one imported board: what it's about, what keeps showing up, how it feels.
private struct BoardSummaryCard: View {
    let collection: TasteCollection
    let onOpen: () -> Void

    var body: some View {
        let distillation = collection.effectiveDistillation(items: [])
        VStack(alignment: .leading, spacing: 18) {
            CoverMosaic(names: collection.coverImageNames)
                .frame(height: 170)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(alignment: .topLeading) {
                    SourceBadge(source: .pinterest, showsLabel: true).padding(10)
                }

            VStack(alignment: .leading, spacing: 6) {
                Text(collection.name).font(.title2.weight(.bold))
                if let summary = collection.summary {
                    Text(summary)
                        .font(.system(.body, design: .serif))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let statement = collection.currentStatement(for: distillation).text {
                Text(statement)
                    .font(Theme.statementFont(.title3))
                    .fixedSize(horizontal: false, vertical: true)
            }

            section("Common elements", counts: Array(distillation.ingredients.prefix(8)), style: .confirmed)
            section("Feelings", counts: Array(distillation.feelings.prefix(6)), style: .neutral)
            section("References", counts: Array(distillation.references.prefix(4)), style: .neutral)

            Button(action: onOpen) {
                Label("Open collection", systemImage: "arrow.right")
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .cardBackground()
    }

    @ViewBuilder
    private func section(_ title: String, counts: [TagCount], style: TagChip.Style) -> some View {
        if !counts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: title)
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(counts) { count in
                        LearnChip(name: count.name, context: "import-\(collection.id)", style: style,
                                  count: "\(count.count)/\(count.total)")
                    }
                }
            }
        }
    }
}
