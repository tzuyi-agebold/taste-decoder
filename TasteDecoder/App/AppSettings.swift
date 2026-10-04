import Foundation
import Observation
import SwiftUI

/// User preferences and Claude configuration.
@Observable
final class AppSettings {
    enum Appearance: String, CaseIterable, Identifiable {
        case dark
        case system

        var id: String { rawValue }
        var label: String { self == .dark ? "Dark" : "Match System" }
    }

    enum KeySource {
        case keychain, buildConfig, none
    }

    static let models: [(id: String, label: String)] = [
        ("claude-opus-5-5", "Claude Opus 5.5 — best"),
        ("claude-sonnet-5-5", "Claude Sonnet 5.5 — faster"),
        ("claude-haiku-4-5", "Claude Haiku 4.5 — fastest"),
    ]

    var model: String {
        didSet { UserDefaults.standard.set(model, forKey: "claudeModel") }
    }

    var appearance: Appearance {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: "appearance") }
    }

    private(set) var keychainKey: String?

    init() {
        let defaults = UserDefaults.standard
        let buildModel = (Bundle.main.object(forInfoDictionaryKey: "ClaudeModel") as? String).flatMap(Self.cleanBuildValue)
        model = defaults.string(forKey: "claudeModel") ?? buildModel ?? "claude-opus-5-5"
        appearance = Appearance(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .dark
        keychainKey = KeychainStore.read()
    }

    /// Key from Config/Secrets.xcconfig, injected through Info.plist at build time.
    var buildKey: String? {
        (Bundle.main.object(forInfoDictionaryKey: "ClaudeAPIKey") as? String).flatMap(Self.cleanBuildValue)
    }

    var apiKey: String? { keychainKey ?? buildKey }
    var hasAPIKey: Bool { apiKey != nil }

    var keySource: KeySource {
        if keychainKey != nil { return .keychain }
        if buildKey != nil { return .buildConfig }
        return .none
    }

    var colorScheme: ColorScheme? { appearance == .dark ? .dark : nil }

    func saveKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        KeychainStore.save(trimmed)
        keychainKey = trimmed
    }

    func clearKey() {
        KeychainStore.delete()
        keychainKey = nil
    }

    /// Signed in: Claude through the Taste Decoder backend (its key, your session).
    /// Signed out: your own key from Settings or Secrets.xcconfig.
    func client() throws -> ClaudeClient {
        if Backend.isSignedIn, let url = Backend.claudeProxyURL, let anonKey = Backend.anonKey {
            return ClaudeClient(transport: .proxy(url: url, apiKey: anonKey, accessToken: { try await Backend.accessToken() }),
                                model: model)
        }
        guard let apiKey else { throw ClaudeClient.ClaudeError.missingKey }
        return ClaudeClient(apiKey: apiKey, model: model)
    }

    /// Whether AI features can run right now (signed in, or a key is set).
    var canUseClaude: Bool { isSignedIn || hasAPIKey }

    /// Mirrors the account (kept in step by RootView) so views refresh when you sign in or out.
    var isSignedIn = Backend.isSignedIn

    private static func cleanBuildValue(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else { return nil }
        return trimmed
    }
}
