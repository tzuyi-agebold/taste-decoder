import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var keyDraft = ""
    @State private var confirmReset = false
    @State private var restoredTick = 0

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            Form {
                Section {
                    SecureField("sk-ant-…", text: $keyDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(saveKey)
                    Button("Save key", action: saveKey)
                        .disabled(keyDraft.nilIfBlank == nil)
                    LabeledContent("Status", value: keyStatus)
                    if settings.keySource == .keychain {
                        Button("Remove saved key", role: .destructive) { settings.clearKey() }
                    }
                    Picker("Model", selection: $settings.model) {
                        ForEach(AppSettings.models, id: \.id) { model in
                            Text(model.label).tag(model.id)
                        }
                    }
                } header: {
                    Text("Claude")
                } footer: {
                    Text("Claude suggests tags (you approve every one), polishes taste statements and writes Learn cards. Counting is always done on your phone. The key is stored in this device's Keychain.")
                }

                Section("Appearance") {
                    Picker("Theme", selection: $settings.appearance) {
                        ForEach(AppSettings.Appearance.allCases) { appearance in
                            Text(appearance.label).tag(appearance)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Button("Restore demo collections") {
                        SeedData.insertAll(context, includeInbox: false)
                        restoredTick += 1
                    }
                    Button("Reset everything", role: .destructive) { confirmReset = true }
                } header: {
                    Text("Demo data")
                } footer: {
                    Text("Restore brings back any missing example collections: Uncomfy, Reds I Love, Rooms and 2am Songs.")
                }

                Section {
                    Text("Taste is only an advantage if you can articulate it. Save fast, then ask why: what does it feel like, what does it remind you of, and what exactly is in it.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                    if !AppGroup.isAvailable {
                        Label("App Group unavailable — saving from the Share Sheet is off. See the README.", systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Reset everything?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Delete all saves and restore the demo", role: .destructive) {
                    SeedData.resetAll(context)
                    restoredTick += 1
                }
            } message: {
                Text("This deletes your saves, collections, tags and cached Learn cards.")
            }
            .sensoryFeedback(.success, trigger: restoredTick)
        }
    }

    private var keyStatus: String {
        switch settings.keySource {
        case .keychain: "Saved on this device"
        case .buildConfig: "From Secrets.xcconfig"
        case .none: "Not set"
        }
    }

    private func saveKey() {
        guard let key = keyDraft.nilIfBlank else { return }
        settings.saveKey(key)
        keyDraft = ""
    }
}
