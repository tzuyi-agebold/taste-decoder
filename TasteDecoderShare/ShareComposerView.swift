import SwiftUI

/// The share sheet UI: one tap to save; a note and a collection if you want them.
struct ShareComposerView: View {
    @Bindable var model: ShareModel

    private let lime = Color(red: 0.80, green: 1.0, blue: 0.24)

    var body: some View {
        NavigationStack {
            Group {
                if model.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if model.groupUnavailable {
                    ContentUnavailableView {
                        Label("Can't save from here yet", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text("Saving from the share sheet needs an App Group. See “Share Extension” in the README.")
                    }
                } else if !model.hasContent {
                    ContentUnavailableView {
                        Label("Nothing to save", systemImage: "questionmark.square.dashed")
                    } description: {
                        Text("Taste Decoder can save images, links and text.")
                    }
                } else {
                    form
                }
            }
            .navigationTitle("Taste Decoder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { model.cancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { model.save() }
                        .fontWeight(.semibold)
                        .disabled(model.isLoading || model.isSaving || !model.hasContent || model.groupUnavailable)
                }
            }
        }
        .tint(lime)
        .preferredColorScheme(.dark)
    }

    private var form: some View {
        Form {
            Section {
                preview
            } footer: {
                Text("Save now. Ask yourself why later, in Taste Decoder.")
            }

            Section("Why did you save this?") {
                TextField("Optional — first instinct is fine", text: $model.note, axis: .vertical)
                    .lineLimit(1...4)
            }

            if !model.collections.isEmpty {
                Section {
                    Picker("Save to", selection: $model.collectionID) {
                        Label("Inbox", systemImage: "tray").tag(UUID?.none)
                        ForEach(model.collections) { stub in
                            Label(stub.name, systemImage: stub.symbol).tag(Optional(stub.id))
                        }
                    }
                }
            }

            if let error = model.errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var preview: some View {
        if !model.thumbnails.isEmpty {
            HStack(spacing: 6) {
                ForEach(Array(model.thumbnails.enumerated()), id: \.offset) { _, image in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 88, height: 110)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                if model.imageData.count > 3 {
                    Text("+\(model.imageData.count - 3)")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 6)
                }
            }
            .padding(.vertical, 4)
        } else if let url = model.url {
            VStack(alignment: .leading, spacing: 6) {
                if let title = model.pageTitle ?? model.text, !title.isEmpty {
                    Text(title)
                        .font(.headline)
                        .lineLimit(3)
                }
                Label(url.host() ?? url.absoluteString, systemImage: "link")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        } else if let text = model.text {
            Text(text)
                .font(.system(.body, design: .serif))
                .lineLimit(8)
                .padding(.vertical, 4)
        }
    }
}
