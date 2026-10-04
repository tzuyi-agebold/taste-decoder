import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AccountStore.self) private var account
    @Environment(SyncService.self) private var sync
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<TasteCollection> { $0.sourceRaw == "pinterest" }) private var pinterestCollections: [TasteCollection]

    @State private var keyDraft = ""
    @State private var confirmReset = false
    @State private var restoredTick = 0
    @State private var showPinterestImport = false
    @State private var confirmSignOut = false

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            Form {
                if account.isConfigured {
                    accountSection
                    if account.isSignedIn {
                        Section {
                            Button {
                                showPinterestImport = true
                            } label: {
                                HStack(spacing: 12) {
                                    SourceBadge(source: .pinterest, size: 24)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Pinterest").foregroundStyle(.primary)
                                        Text(pinterestCollections.isEmpty ? "Import boards as collections"
                                             : "\(pinterestCollections.count) \(pinterestCollections.count == 1 ? "board" : "boards") imported")
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        } header: {
                            Text("Connections")
                        } footer: {
                            Text("Connect, pick boards, or disconnect from the import screen.")
                        }
                    }
                }

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
                    Text(account.isSignedIn
                         ? "Signed in, Claude runs through your Taste Decoder account — no key needed. A key here is only used when you're signed out. Counting is always done on your phone."
                         : "Claude suggests tags (you approve every one), polishes taste statements and writes Learn cards. Counting is always done on your phone. The key is stored in this device's Keychain.")
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
                Text(account.isSignedIn
                     ? "This deletes your saves, collections, tags and cached Learn cards — on every device signed in to your account."
                     : "This deletes your saves, collections, tags and cached Learn cards.")
            }
            .sensoryFeedback(.success, trigger: restoredTick)
            .sheet(isPresented: $showPinterestImport) {
                PinterestImportView { _ in showPinterestImport = false }
            }
            .confirmationDialog("Sign out?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) {
                    Task {
                        await account.signOut()
                        sync.reset(context)
                    }
                }
            } message: {
                Text("Your collections stay on this iPhone. Sign in again to keep syncing.")
            }
        }
    }

    // MARK: Account

    @ViewBuilder
    private var accountSection: some View {
        Section {
            if let user = account.account {
                HStack(spacing: 12) {
                    AsyncImage(url: user.avatarURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.name ?? user.email ?? "Signed in")
                        if let email = user.email, user.name != nil {
                            Text(email).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                Button {
                    Task { await sync.sync(context) }
                } label: {
                    HStack {
                        Text("Sync now")
                        Spacer()
                        if sync.phase == .syncing { ProgressView() }
                    }
                }
                .disabled(sync.phase == .syncing)
                LabeledContent("Status", value: syncStatus)
                Button("Sign out", role: .destructive) { confirmSignOut = true }
            } else {
                Button {
                    Task {
                        await account.signInWithGoogle()
                        if account.isSignedIn { await sync.sync(context) }
                    }
                } label: {
                    HStack {
                        Label("Sign in with Google", systemImage: "person.crop.circle.badge.plus")
                        Spacer()
                        if account.isWorking { ProgressView() }
                    }
                }
                .disabled(account.isWorking)
                if let message = account.errorMessage {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Account")
        } footer: {
            Text(account.isSignedIn
                 ? "Your collections, saves, tags and images are backed up to your account and restored when you sign in on another device."
                 : "Optional. Sign in to back up and sync your saves, use Claude without your own key, and import Pinterest boards.")
        }
    }

    private var syncStatus: String {
        switch sync.phase {
        case .syncing: return "Syncing…"
        case let .failed(message): return "Couldn't sync: \(message)"
        case .idle:
            guard let date = sync.lastSyncedAt else { return "Not synced yet" }
            return "Synced \(date.formatted(.relative(presentation: .named)))"
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
