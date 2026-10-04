import Foundation
import Supabase

// The app's side of the pinterest-* Edge Functions. Pinterest tokens stay on the server;
// the app only ever sees boards and pins. (Foundation + Supabase only.)

struct PinterestBoard: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let description: String?
    let pinCount: Int
    let privacy: String
    let coverImageURL: String?
    let thumbnailURLs: [String]
    let url: String?

    var isSecret: Bool { privacy != "public" }
}

struct PinterestPin: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String?
    let description: String?
    let link: String?
    let altText: String?
    let dominantColor: String?
    let imageURL: String?

    /// The words that came with the pin, for Claude.
    var text: String? {
        let parts = [title, description, altText].compactMap { $0 }.filter { !$0.isEmpty }
        var seen = Set<String>()
        let unique = parts.filter { seen.insert($0.lowercased()).inserted }
        return unique.isEmpty ? nil : unique.joined(separator: " — ")
    }
}

enum PinterestAPI {
    struct Status: Decodable, Sendable {
        let connected: Bool
        let username: String?
    }

    struct BoardList: Decodable, Sendable {
        let username: String?
        let boards: [PinterestBoard]
    }

    struct PinList: Decodable, Sendable {
        let pins: [PinterestPin]
        let truncated: Bool
    }

    private struct StartResponse: Decodable { let url: String }
    private struct PinsRequest: Encodable { let boardId: String }
    private struct Empty: Encodable {}

    private static func client() throws -> SupabaseClient {
        guard let client = Backend.client else { throw BackendError.notConfigured }
        guard Backend.isSignedIn else { throw BackendError.signedOut }
        return client
    }

    static func status() async throws -> Status {
        let rows: [Status] = try await client().rpc("pinterest_status").execute().value
        return rows.first ?? Status(connected: false, username: nil)
    }

    /// The Pinterest authorize URL to open in a web authentication session.
    static func authorizeURL() async throws -> URL {
        do {
            let response: StartResponse = try await client().functions.invoke(
                "pinterest-start", options: FunctionInvokeOptions(body: Empty())
            )
            guard let url = URL(string: response.url) else { throw BackendError.server("Pinterest sign-in link was invalid.") }
            return url
        } catch {
            throw BackendError.wrap(error)
        }
    }

    static func boards() async throws -> BoardList {
        do {
            return try await client().functions.invoke("pinterest-boards", options: FunctionInvokeOptions(body: Empty()))
        } catch {
            throw BackendError.wrap(error)
        }
    }

    static func pins(boardID: String) async throws -> PinList {
        do {
            return try await client().functions.invoke(
                "pinterest-pins", options: FunctionInvokeOptions(body: PinsRequest(boardId: boardID), timeoutInterval: 90)
            )
        } catch {
            throw BackendError.wrap(error)
        }
    }

    static func disconnect() async throws {
        do {
            try await client().functions.invoke("pinterest-disconnect", options: FunctionInvokeOptions(body: Empty()))
        } catch {
            throw BackendError.wrap(error)
        }
    }

    /// Reads the result Pinterest's callback handed back to the app (`tastedecoder://pinterest?status=connected`).
    static func callbackResult(_ url: URL) -> Result<Void, BackendError> {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if items.contains(where: { $0.name == "status" && $0.value == "connected" }) { return .success(()) }
        let reason = items.first { $0.name == "error" }?.value
        return .failure(.server(reason == "denied"
            ? "Pinterest access wasn't allowed."
            : "Couldn't connect Pinterest. Try again."))
    }
}
