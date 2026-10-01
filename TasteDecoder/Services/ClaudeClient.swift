import Foundation

/// Minimal Claude Messages API client over URLSession (there's no official Swift SDK).
/// Every call uses structured outputs (`output_config.format`) so responses decode straight into Swift types.
struct ClaudeClient {
    let apiKey: String
    let model: String

    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let apiVersion = "2023-06-01"
    /// Server-side refusal fallback: a declined request is re-run on a recommended model inside the same call.
    static let fallbackBeta = "server-side-fallback-2026-07-01"

    struct ImageInput {
        let data: Data
        var mediaType = "image/jpeg"
    }

    enum Effort: String {
        case low, medium, high
    }

    enum ClaudeError: LocalizedError {
        case missingKey
        case http(status: Int, message: String)
        case refusal
        case truncated
        case emptyResponse
        case decoding(String)
        case network(String)

        var errorDescription: String? {
            switch self {
            case .missingKey: "Add your Claude API key in Settings to use AI suggestions."
            case let .http(status, message):
                switch status {
                case 401: "Claude rejected the API key. Check it in Settings."
                case 429: "Claude is rate-limiting requests. Try again in a moment."
                case 529, 503: "Claude is overloaded right now. Try again in a moment."
                default: "Claude returned an error (\(status)): \(message)"
                }
            case .refusal: "Claude declined this request."
            case .truncated: "Claude's answer was cut off. Try again."
            case .emptyResponse: "Claude didn't return anything. Try again."
            case let .decoding(detail): "Couldn't read Claude's answer (\(detail))."
            case let .network(detail): "Couldn't reach Claude: \(detail)"
            }
        }
    }

    /// Whether this model accepts `output_config.effort` (Haiku 4.5 doesn't).
    private var supportsEffort: Bool { !model.hasPrefix("claude-haiku") }
    /// Whether to opt into server-side refusal fallbacks (current Opus and Sonnet models).
    private var supportsFallbacks: Bool { model == "claude-opus-5-5" || model == "claude-sonnet-5-5" }

    /// Sends one request constrained to `schema` and decodes the JSON answer as `T`.
    func structured<T: Decodable>(
        _ type: T.Type,
        system: String,
        prompt: String,
        images: [ImageInput] = [],
        schema: [String: Any],
        effort: Effort = .low,
        maxTokens: Int = 16_000,
        timeout: TimeInterval = 120
    ) async throws -> T {
        var content: [[String: Any]] = images.map { image in
            [
                "type": "image",
                "source": ["type": "base64", "media_type": image.mediaType, "data": image.data.base64EncodedString()],
            ]
        }
        content.append(["type": "text", "text": prompt])

        var outputConfig: [String: Any] = ["format": ["type": "json_schema", "schema": schema]]
        if supportsEffort { outputConfig["effort"] = effort.rawValue }

        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": system,
            "messages": [["role": "user", "content": content]],
            "output_config": outputConfig,
        ]

        let text: String
        if supportsFallbacks {
            body["fallbacks"] = "default"
            do {
                text = try await send(body, beta: Self.fallbackBeta, timeout: timeout)
            } catch ClaudeError.http(400, let message) where message.localizedCaseInsensitiveContains("fallback") {
                // Accounts without the fallback beta: retry once without it.
                body.removeValue(forKey: "fallbacks")
                text = try await send(body, beta: nil, timeout: timeout)
            }
        } else {
            text = try await send(body, beta: nil, timeout: timeout)
        }

        let json = Self.stripCodeFence(text)
        do {
            return try JSONDecoder().decode(T.self, from: Data(json.utf8))
        } catch {
            throw ClaudeError.decoding(String(describing: error).prefix(120).description)
        }
    }

    // MARK: - Transport

    private struct MessageResponse: Decodable {
        struct Block: Decodable {
            let type: String
            let text: String?
        }
        let content: [Block]
        let stop_reason: String?
    }

    private struct ErrorResponse: Decodable {
        struct Detail: Decodable { let message: String }
        let error: Detail
    }

    /// Returns the concatenated text blocks of the response (thinking blocks are skipped).
    private func send(_ body: [String: Any], beta: String?, timeout: TimeInterval) async throws -> String {
        var request = URLRequest(url: Self.endpoint, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        if let beta { request.setValue(beta, forHTTPHeaderField: "anthropic-beta") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        var attempt = 0
        while true {
            attempt += 1
            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await URLSession.shared.data(for: request)
            } catch {
                if attempt < 2, (error as? URLError)?.code != .cancelled { continue }
                throw ClaudeError.network(error.localizedDescription)
            }

            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else {
                let message = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error.message
                    ?? String(data: data, encoding: .utf8) ?? ""
                // Retry once on overload / rate limit / server error.
                if attempt < 2, [429, 500, 502, 503, 529].contains(status) {
                    try await Task.sleep(nanoseconds: 1_500_000_000)
                    continue
                }
                throw ClaudeError.http(status: status, message: message)
            }

            let decoded: MessageResponse
            do {
                decoded = try JSONDecoder().decode(MessageResponse.self, from: data)
            } catch {
                throw ClaudeError.decoding("response envelope")
            }
            switch decoded.stop_reason {
            case "refusal": throw ClaudeError.refusal
            case "max_tokens": throw ClaudeError.truncated
            default: break
            }
            let text = decoded.content.filter { $0.type == "text" }.compactMap(\.text).joined()
            guard !text.isEmpty else { throw ClaudeError.emptyResponse }
            return text
        }
    }

    private static func stripCodeFence(_ text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return trimmed }
        if let newline = trimmed.firstIndex(of: "\n") { trimmed = String(trimmed[trimmed.index(after: newline)...]) }
        if trimmed.hasSuffix("```") { trimmed = String(trimmed.dropLast(3)) }
        return trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - JSON schema helpers

enum JSONSchema {
    static func string(_ description: String? = nil) -> [String: Any] {
        var schema: [String: Any] = ["type": "string"]
        if let description { schema["description"] = description }
        return schema
    }

    static func stringEnum(_ values: [String]) -> [String: Any] {
        ["type": "string", "enum": values]
    }

    static func array(_ items: [String: Any], _ description: String? = nil) -> [String: Any] {
        var schema: [String: Any] = ["type": "array", "items": items]
        if let description { schema["description"] = description }
        return schema
    }

    /// Structured outputs require every object to list all properties as required and disallow extras.
    static func object(_ properties: [(String, [String: Any])]) -> [String: Any] {
        [
            "type": "object",
            "properties": Dictionary(uniqueKeysWithValues: properties),
            "required": properties.map { $0.0 },
            "additionalProperties": false,
        ]
    }
}
