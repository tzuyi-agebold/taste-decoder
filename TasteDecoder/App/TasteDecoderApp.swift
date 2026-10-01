import SwiftData
import SwiftUI

@main
struct TasteDecoderApp: App {
    @State private var settings = AppSettings()
    @State private var library = LearnLibrary()
    private let container: ModelContainer

    init() {
        container = Self.makeContainer()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(library)
                .preferredColorScheme(settings.colorScheme)
        }
        .modelContainer(container)
    }

    /// Local-only SwiftData store. If the store can't be opened, fall back to memory so the app still launches.
    private static func makeContainer() -> ModelContainer {
        let schema = Schema([TasteCollection.self, SaveItem.self, TagEntry.self, LearnCardRecord.self])
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
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { ShareImporter.importPending(into: context) }
        }
    }
}
