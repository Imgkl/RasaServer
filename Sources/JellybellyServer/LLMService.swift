import Foundation
import AsyncHTTPClient
import Logging

final class LLMService: Sendable {
    private let httpClient: HTTPClient
    private let logger = Logger(label: "LLMService")
    private let anthropicModel: String
    
    init(httpClient: HTTPClient) {
        self.httpClient = httpClient
        self.anthropicModel = ProcessInfo.processInfo.environment["ANTHROPIC_MODEL"] ?? "claude-sonnet-4-20250514"
    }
    
    func generateTags(
        for movie: Movie,
        using provider: LLMProvider,
        availableTags: [String: MoodBucket],
        customPrompt: String?,
        maxTags: Int = 4,
        externalInfo: String? = nil
    ) async throws -> AutoTagResponse {
        
        let movieContext = buildMovieContext(movie: movie)
        let tagsContext = buildTagsContext(availableTags: availableTags)
        let prompt = buildPrompt(
            movieContext: movieContext,
            tagsContext: tagsContext,
            customPrompt: customPrompt,
            maxTags: maxTags,
            externalInfo: externalInfo
        )
        
        logger.info("Generating tags for movie: \(movie.title) using \(provider.name)")
        
        switch provider {
        case .anthropic(let apiKey):
            return try await generateWithAnthropic(prompt: prompt, apiKey: apiKey, maxTags: maxTags)
        }
    }

    func refineTags(
        for movie: Movie,
        using provider: LLMProvider,
        availableTags: [String: MoodBucket],
        initial: AutoTagResponse,
        externalInfo: String?,
        maxTags: Int
    ) async throws -> AutoTagResponse {
        let movieContext = buildMovieContext(movie: movie)
        let tagsContext = buildTagsContext(availableTags: availableTags)
        let prompt = buildRefinePrompt(
            movieContext: movieContext,
            tagsContext: tagsContext,
            initial: initial,
            externalInfo: externalInfo,
            maxTags: maxTags
        )
        switch provider {
        case .anthropic(let apiKey):
            return try await generateWithAnthropic(prompt: prompt, apiKey: apiKey, maxTags: maxTags)
        }
    }
    
    // MARK: - Anthropic Integration
    
    private func generateWithAnthropic(prompt: String, apiKey: String, maxTags: Int) async throws -> AutoTagResponse {
        let url = "https://api.anthropic.com/v1/messages"
        
        let requestBody = AnthropicRequest(
            model: anthropicModel,
            maxTokens: 500,
            messages: [
                AnthropicMessage(
                    role: "user",
                    content: [AnthropicContent(type: "text", text: prompt)]
                )
            ],
            system: "You are a film expert helping categorize movies by mood. Return only valid JSON."
        )
        
        var request = HTTPClientRequest(url: url)
        request.method = .POST
        request.headers.add(name: "x-api-key", value: apiKey)
        request.headers.add(name: "anthropic-version", value: "2023-06-01")
        request.headers.add(name: "content-type", value: "application/json")
        
        let jsonData = try JSONEncoder().encode(requestBody)
        request.body = .bytes(jsonData)
        
        let response: HTTPClientResponse
        do {
            response = try await httpClient.execute(request, timeout: .seconds(45))
        } catch {
            // Map low-level HTTP client errors to an LLMError so middleware returns a clean 502
            throw LLMError.httpError(502, "Network error contacting Anthropic: \(error.localizedDescription)")
        }
        
        guard response.status == .ok else {
            throw LLMError.httpError(response.status.code, "Anthropic API error")
        }
        
        let data = try await response.body.collect(upTo: 1024 * 1024)
        let anthropicResponse = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        
        guard let content = anthropicResponse.content.first?.text else {
            throw LLMError.invalidResponse("No content in Anthropic response")
        }
        
        return try parseTagResponse(content)
    }
    
    // MARK: - Prompt Building
    
    private func buildMovieContext(movie: Movie) -> String {
        let context = [
            "Title: \(movie.title)",
            movie.originalTitle.map { "Original Title: \($0)" },
            movie.year.map { "Year: \($0)" },
            movie.overview.map { "Plot: \($0)" },
            movie.runtimeMinutes.map { "Runtime: \($0) minutes" },
            movie.director.map { "Director: \($0)" },
            !movie.genres.isEmpty ? "Genres: \(movie.genres.joined(separator: ", "))" : nil,
            !movie.cast.isEmpty ? "Cast: \(movie.cast.prefix(5).joined(separator: ", "))" : nil
        ].compactMap { $0 }
        
        return context.joined(separator: "\n")
    }
    
    private func buildTagsContext(availableTags: [String: MoodBucket]) -> String {
        let tags = availableTags.map { slug, bucket in
            let keywords = (bucket.tags ?? []).joined(separator: ", ")
            let extras = keywords.isEmpty ? "" : " [keywords: \(keywords)]"
            return "\(slug): \(bucket.title) - \(bucket.description)\(extras)"
        }.sorted().joined(separator: "\n")
        
        return "Available mood tags:\n\(tags)"
    }
    
    private func buildPrompt(
        movieContext: String,
        tagsContext: String,
        customPrompt: String?,
        maxTags: Int,
        externalInfo: String?
    ) -> String {
        let basePrompt = customPrompt ?? """
        You are a meticulous film taxonomy expert selecting the most relevant mood tags for a movie.
        Task: Suggest up to \(maxTags) tags (fewer if uncertain) strictly from the provided list.
        Rules:
        - Only choose tags you can justify with explicit evidence from the overview or external summary.
        - DO NOT pick "dialogue-driven" unless dialogue is clearly the dominant engine of tension/plot, with minimal action/set pieces.
        - "time-twists" requires explicit temporal mechanics (time loop/travel/branching timelines). Nonlinear romance is NOT enough.
        - "psychological-pressure-cooker" requires claustrophobic psychological strain; if the tension is mainly spatial confinement with debate, consider "one-room-pressure-cooker" instead.
        - Prefer precision over breadth; if unsure, return fewer than \(maxTags) tags.
        - Calibrate confidence to 0.70–0.95 when evidence is strong; lower only when evidence is weak.
        - Tags MUST be valid slugs from the list. Do not invent new tags.
        Return concise reasoning citing the concrete details that justify each tag.
        """
        
        return """
        \(basePrompt)
        
        Movie information:
        \(movieContext)
        
        \(tagsContext)
        
        Additional external context (optional):
        \(externalInfo ?? "(none)")
        
        Please respond with a JSON object in exactly this format:
        {
            "suggestions": ["tag-slug-1", "tag-slug-2"],
            "confidence": 0.85,
            "reasoning": "Brief explanation of why these tags fit"
        }
        
        Return only valid JSON, nothing else.
        """
    }

    private func buildRefinePrompt(
        movieContext: String,
        tagsContext: String,
        initial: AutoTagResponse,
        externalInfo: String?,
        maxTags: Int
    ) -> String {
        let critiqueGuardrails = """
        You are refining an earlier set of tags. Strict constraints:
        - Keep at most \(maxTags) tags; return fewer if any tag lacks direct evidence.
        - Remove tags that are generic or weakly supported.
        - Reject "time-twists" without explicit temporal mechanics. Nonlinear romance ≠ time travel/loop.
        - If tension is primarily debate in a single space, prefer "one-room-pressure-cooker" over "psychological-pressure-cooker" unless mental unraveling is explicit.
        - If a tag is kept, briefly state the exact evidence (from overview/summary) that justifies it.
        Output format must match exactly:
        {"suggestions": ["tag-1", "tag-2"], "confidence": 0.8, "reasoning": "..."}
        """
        return """
        \(critiqueGuardrails)
        
        Movie information:
        \(movieContext)
        
        \(tagsContext)
        
        Additional external context (optional):
        \(externalInfo ?? "(none)")
        
        Initial tags to critique:
        {"suggestions": \(try! initial.toJSONString()), "note": "Only use the 'suggestions' from above; re-evaluate them."}
        """
    }
    
    // MARK: - Response Parsing
    
    private func parseTagResponse(_ content: String) throws -> AutoTagResponse {
        // Clean up the response - sometimes LLMs add markdown formatting
        let cleanContent = content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let data = cleanContent.data(using: .utf8) else {
            throw LLMError.invalidResponse("Could not encode response as UTF-8")
        }
        
        do {
            return try JSONDecoder().decode(AutoTagResponse.self, from: data)
        } catch {
            logger.error("Failed to parse LLM response: \(cleanContent)")
            throw LLMError.invalidResponse("Failed to parse JSON response: \(error)")
        }
    }
}

// MARK: - LLM Provider

enum LLMProvider: Sendable {
    case anthropic(apiKey: String)
    
    var name: String {
        switch self {
        case .anthropic: return "Anthropic"
        }
    }
    
    static func from(provider: String, apiKey: String) -> LLMProvider? {
        switch provider.lowercased() {
        case "anthropic": return .anthropic(apiKey: apiKey)
        default: return nil
        }
    }
}

// MARK: - External Info

extension LLMService {
    struct WikiSummary: Decodable { let extract: String? }
    
    func fetchExternalSummary(for movie: Movie) async -> String? {
        let base = "https://en.wikipedia.org/api/rest_v1/page/summary/"
        var candidates: [String] = []
        if let year = movie.year {
            candidates.append("\(movie.title) (\(year))")
        }
        candidates.append(movie.title)
        
        for title in candidates {
            let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title
            let url = base + encoded
            var req = HTTPClientRequest(url: url)
            req.method = .GET
            do {
                let resp = try await httpClient.execute(req, timeout: .seconds(8))
                guard resp.status == .ok else { continue }
                let data = try await resp.body.collect(upTo: 512 * 1024)
                let decoded = try? JSONDecoder().decode(WikiSummary.self, from: data)
                if let extract = decoded?.extract, !extract.isEmpty {
                    return extract
                }
            } catch {
                continue
            }
        }
        return nil
    }
}

// MARK: - API Models

// Anthropic
struct AnthropicRequest: Codable {
    let model: String
    let maxTokens: Int
    let messages: [AnthropicMessage]
    let system: String
    
    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case messages
        case system
    }
}

struct AnthropicMessage: Codable {
    let role: String
    let content: [AnthropicContent]
}

struct AnthropicResponse: Codable {
    let content: [AnthropicContent]
    let model: String
    let role: String
    let stopReason: String?
    
    enum CodingKeys: String, CodingKey {
        case content
        case model
        case role
        case stopReason = "stop_reason"
    }
}

struct AnthropicContent: Codable {
    let type: String
    let text: String
}

// Removed Gemini support

// MARK: - Errors

enum LLMError: Error, CustomStringConvertible {
    case httpError(UInt, String)
    case invalidResponse(String)
    case unsupportedProvider(String)
    case missingApiKey(String)
    
    var description: String {
        switch self {
        case .httpError(let code, let message):
            return "LLM API Error (\(code)): \(message)"
        case .invalidResponse(let details):
            return "Invalid LLM response: \(details)"
        case .unsupportedProvider(let provider):
            return "Unsupported LLM provider: \(provider)"
        case .missingApiKey(let provider):
            return "Missing API key for \(provider)"
        }
    }
}
