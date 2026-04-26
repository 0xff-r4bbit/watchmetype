import Foundation

enum HumanizerError: LocalizedError {
    case networkError(Error)
    case invalidResponse(String)
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse(let detail):
            return "Invalid response from humanizer service: \(detail)"
        case .serverError(let message):
            return "Humanizer service error: \(message)"
        }
    }
}

struct HumanizerService {
    private static let promptURL = URL(string: "https://raw.githubusercontent.com/nicojan/humanize-text-prompt/refs/heads/main/PROMPT.md")!
    private static var cachedGuide: String?

    static func fetchGuide(ignoreCache: Bool = false) async throws -> String {
        if !ignoreCache, let cached = cachedGuide {
            appLog("Returning cached humanizer guide", level: .debug)
            return cached
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(from: promptURL)
        } catch {
            appLog("Humanizer network request failed: \(error)", level: .error)
            throw HumanizerError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw HumanizerError.invalidResponse("Not an HTTP response")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "no body"
            throw HumanizerError.serverError("HTTP \(httpResponse.statusCode): \(body)")
        }

        guard let raw = String(data: data, encoding: .utf8) else {
            throw HumanizerError.invalidResponse("Could not decode response as UTF-8")
        }

        let guide = stripFrontmatter(raw)

        guard !guide.isEmpty else {
            throw HumanizerError.invalidResponse("PROMPT.md contained no content after frontmatter")
        }

        cachedGuide = guide
        appLog("Humanizer guide fetched successfully (\(guide.count) chars)", level: .debug)
        return guide
    }

    static func clearCache() {
        cachedGuide = nil
    }

    // MARK: - Content Stripping

    /// Strips YAML frontmatter (delimited by "---" at the top) and any intro
    /// text above the first standalone "---" horizontal rule.
    private static func stripFrontmatter(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Handle YAML frontmatter (starts with "---")
        if trimmed.hasPrefix("---") {
            let afterOpening = trimmed.index(trimmed.startIndex, offsetBy: 3)
            let rest = trimmed[afterOpening...]

            if let closingRange = rest.range(of: "\n---") {
                let afterClosing = closingRange.upperBound
                return String(rest[afterClosing...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // No YAML frontmatter — strip intro above the first "---" horizontal rule
        // (a line that is exactly "---" surrounded by blank lines or at line boundaries)
        let lines = trimmed.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            let stripped = line.trimmingCharacters(in: .whitespaces)
            if stripped == "---" && index > 0 {
                let remaining = lines[(index + 1)...].joined(separator: "\n")
                let result = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
                if !result.isEmpty {
                    return result
                }
            }
        }

        return trimmed
    }
}
