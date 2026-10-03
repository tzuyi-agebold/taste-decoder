import SwiftData
import SwiftUI

@main
struct TasteDecoderApp: App {
    @State private var settings = AppSettings()
    @State private var library = LearnLibrary()
    @State private var account = AccountStore()
    @State private var sync = SyncService()
    private let container: ModelContainer

    init() {
        container = Self.makeContainer()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(library)
                .environment(account)
                .environment(sync)
                .preferredColorScheme(settings.colorScheme)
        }
        .modelContainer(container)
    }

    /// Local-only SwiftData store. If the store can't be opened, fall back to memory so the app still launches.
    private static func makeContainer() -> ModelContainer {
        let schema = Schema([TasteCollection.self, SaveItem.self, TagEntry.self, LearnCardRecord.self, SyncRecord.self])
        do {
            return try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema))
        } catch {
            print("Taste Decoder: couldn't open the store (\(error)); using an in-memory store.")
            // swiftlint:disable:next force_try
            return try! ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        }
    }
}

enum AppTab: String {
    case save, collections, pantry, learn
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppSettings.self) private var settings
    @Environment(AccountStore.self) private var account
    @Environment(SyncService.self) private var sync
    @SceneStorage("selectedTab") private var tab: AppTab = .collections

    var body: some View {
        TabView(selection: $tab) {
            SaveView()
                .tabItem { Label("Save", systemImage: "tray.and.arrow.down") }
                .tag(AppTab.save)
            CollectionsView()
                .tabItem { Label("Collections", systemImage: "square.stack") }
                .tag(AppTab.collections)
            PantryView()
                .tabItem { Label("Pantry", systemImage: "books.vertical") }
                .tag(AppTab.pantry)
            LearnHomeView()
                .tabItem { Label("Learn", systemImage: "graduationcap") }
                .tag(AppTab.learn)
        }
        .task {
            SeedData.seedIfNeeded(context)
            ShareImporter.importPending(into: context)
            settings.isSignedIn = account.isSignedIn
            await sync.sync(context)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                ShareImporter.importPending(into: context)
                Task { await sync.sync(context) }
            case .background:
                // Push what changed while the app was open.
                Task { await sync.sync(context) }
            default:
                break
            }
        }
        .onChange(of: account.account?.id) { _, id in
            settings.isSignedIn = id != nil
            if id != nil { Task { await sync.sync(context) } }
        }
        .onOpenURL { url in
            // Google Sign-In's redirect. (Pinterest's comes back through ASWebAuthenticationSession.)
            _ = account.handle(url)
        }
    }
}
