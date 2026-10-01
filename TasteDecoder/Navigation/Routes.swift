import SwiftUI

// Navigation values and the shared destinations every tab's NavigationStack registers.

/// Opens a Learn card. `sourceID` identifies the tapped chip so the card can zoom out of it (iOS 18+).
struct LearnRoute: Hashable {
    let name: String
    let sourceID: String

    init(name: String, context: String) {
        self.name = name
        self.sourceID = "\(context)|\(TagText.key(name))"
    }
}

struct DistillRoute: Hashable {
    let collection: TasteCollection
}

struct CompareRoute: Hashable {
    var firstID: UUID?
    var secondID: UUID?
}

/// A batch of saves to interrogate in a row.
struct InterrogationQueue: Identifiable {
    let id = UUID()
    let items: [SaveItem]
}

// MARK: - Zoom transition namespace

private struct LearnNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    var learnNamespace: Namespace.ID? {
        get { self[LearnNamespaceKey.self] }
        set { self[LearnNamespaceKey.self] = newValue }
    }
}

extension View {
    /// Marks a view as the origin of a zoom transition (iOS 18+; no-op on iOS 17).
    @ViewBuilder
    func zoomSource(id: String, in namespace: Namespace.ID?) -> some View {
        if #available(iOS 18.0, *) {
            if let namespace {
                self.matchedTransitionSource(id: id, in: namespace)
            } else {
                self
            }
        } else {
            self
        }
    }

    /// Makes a pushed view zoom out of its source (iOS 18+; standard push on iOS 17).
    @ViewBuilder
    func zoomTransition(id: String, in namespace: Namespace.ID?) -> some View {
        if #available(iOS 18.0, *) {
            if let namespace {
                self.navigationTransition(.zoom(sourceID: id, in: namespace))
            } else {
                self
            }
        } else {
            self
        }
    }

    /// Registers the app's navigation destinations. Apply to the root view inside each NavigationStack.
    func tasteDestinations(_ namespace: Namespace.ID) -> some View {
        self
            .environment(\.learnNamespace, namespace)
            .navigationDestination(for: TasteCollection.self) { collection in
                CollectionDetailView(collection: collection)
                    .environment(\.learnNamespace, namespace)
            }
            .navigationDestination(for: SaveItem.self) { item in
                ItemDetailView(item: item)
                    .environment(\.learnNamespace, namespace)
            }
            .navigationDestination(for: DistillRoute.self) { route in
                DistillationView(collection: route.collection)
                    .environment(\.learnNamespace, namespace)
            }
            .navigationDestination(for: CompareRoute.self) { route in
                CompareView(route: route)
                    .environment(\.learnNamespace, namespace)
            }
            .navigationDestination(for: LearnRoute.self) { route in
                LearnCardView(route: route)
                    .environment(\.learnNamespace, namespace)
                    .zoomTransition(id: route.sourceID, in: namespace)
            }
    }
}
