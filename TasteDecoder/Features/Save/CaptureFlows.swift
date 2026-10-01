import PhotosUI
import SwiftData
import SwiftUI
import UIKit

/// Drives the capture sheets from anywhere (Save tab, a collection).
@Observable
final class CaptureController {
    enum Mode {
        case camera, photos, link, note
    }

    var showCamera = false
    var showPhotos = false
    var showLink = false
    var showNote = false
    var cameraUnavailable = false

    func start(_ mode: Mode) {
        switch mode {
        case .camera:
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                showCamera = true
            } else {
                cameraUnavailable = true
            }
        case .photos: showPhotos = true
        case .link: showLink = true
        case .note: showNote = true
        }
    }
}

extension View {
    /// Attaches the camera, photo picker, link and note flows. `onSaved` fires after each save.
    func captureFlows(_ capture: CaptureController, destination: TasteCollection?, onSaved: @escaping () -> Void) -> some View {
        modifier(CaptureFlows(capture: capture, destination: destination, onSaved: onSaved))
    }
}

private struct CaptureFlows: ViewModifier {
    @Bindable var capture: CaptureController
    let destination: TasteCollection?
    let onSaved: () -> Void

    @Environment(\.modelContext) private var context
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var importing = 0

    func body(content: Content) -> some View {
        content
            .photosPicker(isPresented: $capture.showPhotos, selection: $photoItems, maxSelectionCount: 30,
                          selectionBehavior: .ordered, matching: .images)
            .onChange(of: photoItems) { _, newItems in
                importPhotos(newItems)
            }
            .fullScreenCover(isPresented: $capture.showCamera) {
                CameraPicker { image in
                    if Capture.addPhoto(image: image, to: destination, context: context) != nil { onSaved() }
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $capture.showLink) {
                LinkCaptureSheet { url, note in
                    Capture.addLink(url, note: note, to: destination, context: context)
                    onSaved()
                }
            }
            .sheet(isPresented: $capture.showNote) {
                NoteCaptureSheet { text in
                    Capture.addNote(text, to: destination, context: context)
                    onSaved()
                }
            }
            .alert("Camera unavailable", isPresented: $capture.cameraUnavailable) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("This device doesn't have a camera available. Try Photos instead.")
            }
            .overlay(alignment: .bottom) {
                if importing > 0 {
                    Label("Saving \(importing) \(importing == 1 ? "photo" : "photos")…", systemImage: "arrow.down.circle")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(Theme.spring, value: importing)
    }

    private func importPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        let target = destination
        importing = items.count
        Task { @MainActor in
            var saved = 0
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    let fileName = await Task.detached(priority: .userInitiated) { ImageStore.save(data: data) }.value
                    if let fileName {
                        Capture.insertPhoto(fileName: fileName, to: target, context: context)
                        saved += 1
                    }
                }
                importing = max(importing - 1, 0)
            }
            photoItems = []
            importing = 0
            if saved > 0 { onSaved() }
        }
    }
}

extension Capture {
    @discardableResult
    static func insertPhoto(fileName: String, to collection: TasteCollection?, context: ModelContext) -> SaveItem {
        let item = SaveItem(kind: .photo, imageFileName: fileName)
        context.insert(item)
        item.collection = collection
        try? context.save()
        return item
    }
}

// MARK: - Sheets

struct LinkCaptureSheet: View {
    let onSave: (URL, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var note = ""
    @FocusState private var focused: Bool

    private var url: URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = Capture.webURL(from: trimmed) { return url }
        if trimmed.contains("."), !trimmed.contains("://") { return Capture.webURL(from: "https://" + trimmed) }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://", text: $text)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit(save)
                    PasteButton(payloadType: String.self) { strings in
                        Task { @MainActor in text = strings.first ?? text }
                    }
                    .labelStyle(.titleAndIcon)
                } footer: {
                    Text("Paste a link from anywhere. Taste Decoder grabs its preview image so you can decode it later.")
                }
                Section("Why did you save this?") {
                    TextField("Optional — first instinct is fine", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .navigationTitle("Save a link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(url == nil)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        guard let url else { return }
        onSave(url, note.nilIfBlank)
        dismiss()
    }
}

struct NoteCaptureSheet: View {
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("A song, a room, a meal, a line from a film…", text: $text, axis: .vertical)
                        .lineLimit(4...12)
                        .focused($focused)
                } footer: {
                    Text("Describe what you noticed. You'll decode why later.")
                }
            }
            .navigationTitle("Save a note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(text.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(text.nilIfBlank == nil)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
    }
}

/// UIKit camera wrapped for SwiftUI.
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
