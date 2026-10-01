import SwiftData
import SwiftUI

/// Two collections side by side. The overlap is the common ground — the start of a conversation.
struct CompareView: View {
    let route: CompareRoute

    @Query(sort: \TasteCollection.sortIndex) private var collections: [TasteCollection]
    @Query private var allItems: [SaveItem]
    @Query(filter: #Predicate<TagEntry> { $0.statusRaw == "confirmed" }) private var confirmedTags: [TagEntry]

    @State private var firstID: UUID?
    @State private var secondID: UUID?
    @State private var didSetDefaults = false

    var body: some View {
        let first = collections.first { $0.id == firstID }
        let second = collections.first { $0.id == secondID }

        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                pickers(first: first, second: second)

                if let first, let second {
                    let a = distillation(first)
                    let b = distillation(second)
                    let comparison = Comparer.compare(a, b)

                    VennHeader(comparison: comparison)
                        .frame(maxWidth: .infinity)

                    Text(comparison.sentence(nameA: first.name, nameB: second.name))
                        .font(Theme.statementFont(.title2))
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.opacity)

                    commonGround(comparison, first: first, second: second)
                    divergence(comparison, first: first, second: second)

                    ShareLink(item: shareText(comparison, first: first, second: second)) {
                        Label("Share this common ground", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                } else {
                    ContentUnavailableView {
                        Label("Pick two collections", systemImage: "square.split.2x1")
                    } description: {
                        Text("See what they share — and where they split.")
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
            .animation(Theme.spring, value: firstID)
            .animation(Theme.spring, value: secondID)
        }
        .navigationTitle("Compare")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: setDefaults)
        .sensoryFeedback(.selection, trigger: firstID)
        .sensoryFeedback(.selection, trigger: secondID)
    }

    // MARK: Sections

    private func pickers(first: TasteCollection?, second: TasteCollection?) -> some View {
        HStack(alignment: .center, spacing: 10) {
            CollectionPickerCard(selection: $firstID, collections: collections, excluding: secondID, label: "A")
            Button {
                withAnimation(Theme.spring) {
                    let previous = firstID
                    firstID = secondID
                    secondID = previous
                }
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.subheadline.weight(.bold))
                    .frame(width: 36, height: 36)
                    .background(Theme.raised, in: Circle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Swap")
            CollectionPickerCard(selection: $secondID, collections: collections, excluding: firstID, label: "B")
        }
    }

    @ViewBuilder
    private func commonGround(_ comparison: Comparison, first: TasteCollection, second: TasteCollection) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: "Common ground",
                         subtitle: comparison.common.isEmpty ? "Nothing shared yet." : "What you like in both — and why.")
            ForEach(TagLevel.allCases) { level in
                let shared = comparison.common(level)
                if !shared.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(level.pluralTitle, systemImage: level.symbol)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        FlowLayout(spacing: 8, lineSpacing: 8) {
                            ForEach(shared) { item in
                                LearnChip(name: item.name, context: "common", style: .common,
                                          count: "\(item.countA) · \(item.countB)")
                            }
                        }
                    }
                }
            }
            if !comparison.common.isEmpty {
                Text("Counts show saves in \(first.name) · \(second.name).")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func divergence(_ comparison: Comparison, first: TasteCollection, second: TasteCollection) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: "Where you split", subtitle: "Strongest ingredients that only one side has.")
            HStack(alignment: .top, spacing: 12) {
                divergenceColumn(title: first.name, tags: Array(comparison.onlyA.prefix(8)), context: "only-a")
                divergenceColumn(title: second.name, tags: Array(comparison.onlyB.prefix(8)), context: "only-b")
            }
        }
    }

    private func divergenceColumn(title: String, tags: [TagCount], context: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Only in \(title)")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            if tags.isEmpty {
                Text("—").foregroundStyle(.tertiary)
            }
            ForEach(tags) { tag in
                LearnChip(name: tag.name, context: context, style: .muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: Helpers

    private func distillation(_ collection: TasteCollection) -> Distillation {
        Distiller.distill(allItems.filter { $0.collection == collection }.map(\.snapshot))
    }

    /// Starts on the requested pair, or the pair with the most common ground.
    private func setDefaults() {
        guard !didSetDefaults else { return }
        didSetDefaults = true
        firstID = route.firstID ?? firstID
        secondID = route.secondID

        if firstID == nil || secondID == nil {
            let candidates = collections.filter { $0.id != firstID }
            var best: (UUID, UUID, Int)?
            let anchors = firstID.flatMap { id in collections.first { $0.id == id } }.map { [$0] } ?? collections
            for a in anchors {
                for b in candidates where b.id != a.id {
                    let shared = Comparer.compare(distillation(a), distillation(b)).common.count
                    if shared > (best?.2 ?? -1) { best = (a.id, b.id, shared) }
                }
            }
            if let best {
                firstID = best.0
                secondID = best.1
            }
        }
    }

    private func shareText(_ comparison: Comparison, first: TasteCollection, second: TasteCollection) -> String {
        var lines = [comparison.sentence(nameA: first.name, nameB: second.name)]
        if !comparison.common.isEmpty {
            lines.append("Common ground: " + comparison.common.prefix(8).map(\.name).joined(separator: ", "))
        }
        if let a = comparison.onlyA.first, let b = comparison.onlyB.first {
            lines.append("Where we split: \(first.name) leans \(a.name); \(second.name) leans \(b.name).")
        }
        lines.append("— decoded with Taste Decoder")
        return lines.joined(separator: "\n")
    }
}

// MARK: - Pieces

private struct CollectionPickerCard: View {
    @Binding var selection: UUID?
    let collections: [TasteCollection]
    let excluding: UUID?
    let label: String

    var body: some View {
        let selected = collections.first { $0.id == selection }
        Menu {
            ForEach(collections.filter { $0.id != excluding }) { collection in
                Button {
                    selection = collection.id
                } label: {
                    Label(collection.name, systemImage: collection.id == selection ? "checkmark" : collection.symbol)
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Group {
                    if let selected, !selected.items.isEmpty {
                        Mosaic(items: selected.sortedItems)
                    } else {
                        ZStack {
                            Theme.raised
                            Image(systemName: selected?.symbol ?? "plus")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                HStack(spacing: 6) {
                    Text(label)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.onAccent)
                        .frame(width: 20, height: 20)
                        .background(Theme.accent, in: Circle())
                    Text(selected?.name ?? "Choose")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .frame(maxWidth: .infinity)
    }
}

/// Two overlapping circles; the lens between them is the common ground.
private struct VennHeader: View {
    let comparison: Comparison

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.raised)
                .frame(width: 150, height: 150)
                .offset(x: -48)
            Circle()
                .fill(Theme.raised)
                .frame(width: 150, height: 150)
                .offset(x: 48)
            LensShape(offset: 48, diameter: 150)
                .fill(Theme.accent)
                .opacity(comparison.common.isEmpty ? 0.15 : 1)
            HStack(spacing: 0) {
                count(comparison.onlyA.count, label: "only A")
                    .frame(width: 90)
                count(comparison.common.count, label: "shared", onAccent: !comparison.common.isEmpty)
                    .frame(width: 64)
                count(comparison.onlyB.count, label: "only B")
                    .frame(width: 90)
            }
        }
        .frame(height: 160)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(comparison.common.count) shared, \(comparison.onlyA.count) only in A, \(comparison.onlyB.count) only in B")
    }

    private func count(_ value: Int, label: String, onAccent: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.title.weight(.bold))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(value)))
            Text(label)
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
        }
        .foregroundStyle(onAccent ? Theme.onAccent : .primary)
    }
}

/// The intersection of two circles centered ±offset from the middle.
private struct LensShape: Shape {
    let offset: CGFloat
    let diameter: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = diameter / 2
        let left = Path(ellipseIn: CGRect(x: rect.midX - offset - radius, y: rect.midY - radius, width: diameter, height: diameter))
        let right = Path(ellipseIn: CGRect(x: rect.midX + offset - radius, y: rect.midY - radius, width: diameter, height: diameter))
        return left.intersection(right)
    }
}
