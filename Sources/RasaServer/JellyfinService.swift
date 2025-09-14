import Foundation
import AsyncHTTPClient
import Logging

final class JellyfinService: Sendable {
    private let httpClient: HTTPClient
    private let baseURL: String
    private let apiKey: String
    private let userId: String
    private let logger = Logger(label: "JellyfinService")
    
    init(baseURL: String, apiKey: String, userId: String, httpClient: HTTPClient) {
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.apiKey = apiKey
        self.userId = userId
        self.httpClient = httpClient
    }
    
    // Expose shared client for reuse
    var client: HTTPClient { httpClient }
    
    // MARK: - Authentication (Username/Password)
    
    static func login(baseURL: String, username: String, password: String, httpClient: HTTPClient) async throws -> (token: String, userId: String) {
        let trimmedBase = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let url = "\(trimmedBase)/Users/AuthenticateByName"
        var request = HTTPClientRequest(url: url)
        request.method = .POST
        request.headers.add(name: "Accept", value: "application/json")
        request.headers.add(name: "Content-Type", value: "application/json")
        // Jellyfin requires an identification header
        let deviceId = UUID().uuidString
        let clientHeader = "MediaBrowser Client=\"Rasa\", Device=\"RasaServer\", DeviceId=\"\(deviceId)\", Version=\"1.0.0\""
        request.headers.add(name: "X-Emby-Authorization", value: clientHeader)
        // Minimal Jellyfin auth does not require prior token
        let payload: [String: String] = [
            "Username": username,
            "Pw": password
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        request.body = .bytes(data)
        let response = try await httpClient.execute(request, timeout: .seconds(10))
        guard response.status == .ok else {
            throw JellyfinError.httpError(response.status.code, "Failed to authenticate user")
        }
        let body = try await response.body.collect(upTo: 1024 * 1024)
        let auth = try JSONDecoder().decode(JellyfinAuthResponse.self, from: body)
        return (token: auth.accessToken, userId: auth.user.id)
    }
    
    // MARK: - Movies
    
    func fetchAllMovies() async throws -> [JellyfinMovieMetadata] {
        let url = "\(baseURL)/Users/\(userId)/Items"
        
        var request = HTTPClientRequest(url: url)
        request.method = .GET
        request.headers.add(name: "X-MediaBrowser-Token", value: apiKey)
        request.headers.add(name: "Accept", value: "application/json")
        
        // Query parameters for movies
        let queryItems = [
            "IncludeItemTypes": "Movie",
            "Recursive": "true",
            "Fields": "Overview,Genres,People,MediaStreams,ProviderIds,Studios,Taglines,ProductionYear,PremiereDate,RunTimeTicks,CommunityRating,OfficialRating,ImageBlurHashes,UserData",
            "SortBy": "SortName",
            "SortOrder": "Ascending"
        ]
        
        let queryString = queryItems.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        request.url = "\(url)?\(queryString)"
        
        logger.info("Fetching movies from Jellyfin: \(request.url)")
        
        let response = try await httpClient.execute(request, timeout: .seconds(30))
        
        guard response.status == .ok else {
            throw JellyfinError.httpError(response.status.code, "Failed to fetch movies")
        }
        
        let data = try await response.body.collect(upTo: 10 * 1024 * 1024) // 10MB limit
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        let jellyfinResponse = try decoder.decode(JellyfinItemsResponse.self, from: data)
        
        logger.info("Fetched \(jellyfinResponse.items.count) movies from Jellyfin")
        return jellyfinResponse.items
    }

    /// Fetch items similar to a given item from Jellyfin (movies only)
    func fetchSimilarItems(itemId: String, limit: Int = 12) async throws -> [JellyfinMovieMetadata] {
        // Prefer the Items/{id}/Similar endpoint with explicit UserId for user data overlay
        let base = "\(baseURL)/Items/\(itemId)/Similar"
        let fields = "Overview,Genres,People,MediaStreams,ProviderIds,Studios,RunTimeTicks,UserData,ProductionYear,ImageBlurHashes"
        let url = "\(base)?UserId=\(userId)&IncludeItemTypes=Movie&Limit=\(limit)&Fields=\(fields)"

        var request = HTTPClientRequest(url: url)
        request.method = .GET
        request.headers.add(name: "X-MediaBrowser-Token", value: apiKey)
        request.headers.add(name: "Accept", value: "application/json")

        let response = try await httpClient.execute(request, timeout: .seconds(12))
        guard response.status == .ok else {
            throw JellyfinError.httpError(response.status.code, "Failed to fetch similar items for \(itemId)")
        }
        let data = try await response.body.collect(upTo: 5 * 1024 * 1024)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        let decoded = try decoder.decode(JellyfinItemsResponse.self, from: data)
        return decoded.items
    }

    // Fetch resume/continue-watching items for the user (movies only)
    func fetchResumeItems(limit: Int? = nil) async throws -> [JellyfinMovieMetadata] {
        let base = "\(baseURL)/Users/\(userId)/Items/Resume"
        var url = base + "?IncludeItemTypes=Movie&Fields=Overview,Genres,People,MediaStreams,ProviderIds,Studios,RunTimeTicks,UserData,ProductionYear"
        if let limit = limit, limit > 0 { url += "&Limit=\(limit)" }

        var request = HTTPClientRequest(url: url)
        request.method = .GET
        request.headers.add(name: "X-MediaBrowser-Token", value: apiKey)
        request.headers.add(name: "Accept", value: "application/json")

        let response = try await httpClient.execute(request, timeout: .seconds(12))
        guard response.status == .ok else {
            throw JellyfinError.httpError(response.status.code, "Failed to fetch resume items")
        }
        let data = try await response.body.collect(upTo: 5 * 1024 * 1024)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        let decoded = try decoder.decode(JellyfinItemsResponse.self, from: data)
        return decoded.items
    }

    /// Fetch recently added movies for the user, sorted by DateCreated desc
    func fetchRecentlyAddedMovies(limit: Int = 10) async throws -> [JellyfinMovieMetadata] {
        let base = "\(baseURL)/Users/\(userId)/Items"
        let fields = "Overview,Genres,People,MediaStreams,ProviderIds,Studios,RunTimeTicks,UserData,ProductionYear,ImageBlurHashes"
        let url = "\(base)?IncludeItemTypes=Movie&Recursive=true&SortBy=DateCreated&SortOrder=Descending&Limit=\(limit)&Fields=\(fields)"

        var request = HTTPClientRequest(url: url)
        request.method = .GET
        request.headers.add(name: "X-MediaBrowser-Token", value: apiKey)
        request.headers.add(name: "Accept", value: "application/json")

        let response = try await httpClient.execute(request, timeout: .seconds(12))
        guard response.status == .ok else {
            throw JellyfinError.httpError(response.status.code, "Failed to fetch recently added movies")
        }
        let data = try await response.body.collect(upTo: 5 * 1024 * 1024)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        let decoded = try decoder.decode(JellyfinItemsResponse.self, from: data)
        return decoded.items
    }
    
    func fetchMovie(id: String) async throws -> JellyfinMovieMetadata {
        let url = "\(baseURL)/Users/\(userId)/Items/\(id)"
        
        var request = HTTPClientRequest(url: url)
        request.method = .GET
        request.headers.add(name: "X-MediaBrowser-Token", value: apiKey)
        request.headers.add(name: "Accept", value: "application/json")
        
        let response = try await httpClient.execute(request, timeout: .seconds(10))
        
        guard response.status == .ok else {
            throw JellyfinError.httpError(response.status.code, "Failed to fetch movie \(id)")
        }
        
        let data = try await response.body.collect(upTo: 1024 * 1024) // 1MB limit
        return try JSONDecoder().decode(JellyfinMovieMetadata.self, from: data)
    }
    
    // MARK: - Images
    
    func getImageUrl(itemId: String, imageType: String = "Primary", maxWidth: Int? = nil, quality: Int? = 100) -> String {
        var url = "\(baseURL)/Items/\(itemId)/Images/\(imageType)"
        
        var queryParams: [String] = []
        // if let maxWidth = maxWidth {
        //     queryParams.append("maxWidth=\(maxWidth)")
        // }
        if let quality = quality {
            queryParams.append("quality=\(quality)")
        }
        
        if !queryParams.isEmpty {
            url += "?" + queryParams.joined(separator: "&")
        }
        
        return url
    }
    
    func getPosterUrl(itemId: String) -> String {
        getImageUrl(itemId: itemId, imageType: "Primary", quality: 85)
    }
    
    func getBackdropUrl(itemId: String) -> String {
        getImageUrl(itemId: itemId, imageType: "Backdrop", quality: 85)
    }

    func getLogoUrl(itemId: String) -> String {
        getImageUrl(itemId: itemId, imageType: "Logo", quality: 85)
    }

    
    // MARK: - Playback
    
    func getStreamUrl(itemId: String, container: String = "mkv") -> String {
        "\(baseURL)/Videos/\(itemId)/stream?container=\(container)&api_key=\(apiKey)"
    }
    
    func getHlsStreamUrl(itemId: String) -> String {
        "\(baseURL)/Videos/\(itemId)/master.m3u8?api_key=\(apiKey)"
    }

    // MARK: - Playback Reporting (proxy-friendly helpers)
    func reportPlaybackStart(itemId: String, positionMs: Int?, playMethod: String?, audioStreamIndex: Int?, subtitleStreamIndex: Int?) async throws {
        let url = "\(baseURL)/Sessions/Playing"
        var req = HTTPClientRequest(url: url)
        req.method = .POST
        req.headers.add(name: "X-MediaBrowser-Token", value: apiKey)
        req.headers.add(name: "Accept", value: "application/json")
        req.headers.add(name: "Content-Type", value: "application/json")
        let payload: [String: Any?] = [
            "ItemId": itemId,
            "CanSeek": true,
            "PlayMethod": playMethod ?? "DirectPlay",
            "PositionTicks": positionMs.map { Int64($0) * 10_000 },
            "AudioStreamIndex": audioStreamIndex,
            "SubtitleStreamIndex": subtitleStreamIndex
        ]
        let data = try JSONSerialization.data(withJSONObject: payload.compactMapValues { $0 }, options: [])
        req.body = .bytes(data)
        let resp = try await httpClient.execute(req, timeout: .seconds(8))
        guard resp.status == .ok else { throw JellyfinError.httpError(resp.status.code, "Playback start report failed") }
    }

    func reportPlaybackProgress(itemId: String, positionMs: Int, isPaused: Bool?) async throws {
        let url = "\(baseURL)/Sessions/Playing/Progress"
        var req = HTTPClientRequest(url: url)
        req.method = .POST
        req.headers.add(name: "X-MediaBrowser-Token", value: apiKey)
        req.headers.add(name: "Accept", value: "application/json")
        req.headers.add(name: "Content-Type", value: "application/json")
        let payload: [String: Any] = [
            "ItemId": itemId,
            "PositionTicks": Int64(positionMs) * 10_000,
            "IsPaused": isPaused ?? false
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        req.body = .bytes(data)
        let resp = try await httpClient.execute(req, timeout: .seconds(8))
        guard resp.status == .ok else { throw JellyfinError.httpError(resp.status.code, "Playback progress report failed") }
    }

    func reportPlaybackStopped(itemId: String, positionMs: Int?) async throws {
        let url = "\(baseURL)/Sessions/Playing/Stopped"
        var req = HTTPClientRequest(url: url)
        req.method = .POST
        req.headers.add(name: "X-MediaBrowser-Token", value: apiKey)
        req.headers.add(name: "Accept", value: "application/json")
        req.headers.add(name: "Content-Type", value: "application/json")
        let payload: [String: Any?] = [
            "ItemId": itemId,
            "PositionTicks": positionMs.map { Int64($0) * 10_000 }
        ]
        let data = try JSONSerialization.data(withJSONObject: payload.compactMapValues { $0 }, options: [])
        req.body = .bytes(data)
        let resp = try await httpClient.execute(req, timeout: .seconds(8))
        guard resp.status == .ok else { throw JellyfinError.httpError(resp.status.code, "Playback stop report failed") }
    }

    // MARK: - Watched State
    func markItemPlayed(itemId: String) async throws {
        let url = "\(baseURL)/Users/\(userId)/PlayedItems/\(itemId)"
        var req = HTTPClientRequest(url: url)
        req.method = .POST
        req.headers.add(name: "X-MediaBrowser-Token", value: apiKey)
        req.headers.add(name: "Accept", value: "application/json")
        let resp = try await httpClient.execute(req, timeout: .seconds(8))
        guard (200..<300).contains(resp.status.code) else {
            throw JellyfinError.httpError(resp.status.code, "Failed to mark item played")
        }
    }

    func markItemUnplayed(itemId: String) async throws {
        let url = "\(baseURL)/Users/\(userId)/PlayedItems/\(itemId)"
        var req = HTTPClientRequest(url: url)
        req.method = .DELETE
        req.headers.add(name: "X-MediaBrowser-Token", value: apiKey)
        req.headers.add(name: "Accept", value: "application/json")
        let resp = try await httpClient.execute(req, timeout: .seconds(8))
        guard (200..<300).contains(resp.status.code) else {
            throw JellyfinError.httpError(resp.status.code, "Failed to mark item unplayed")
        }
    }

    // MARK: - Bulk item fetch (UserData + RunTimeTicks)
    func fetchItems(ids: [String]) async throws -> [JellyfinMovieMetadata] {
        guard !ids.isEmpty else { return [] }
        let chunks = ids.chunked(into: 80)
        var aggregated: [JellyfinMovieMetadata] = []
        aggregated.reserveCapacity(ids.count)

        for c in chunks {
            let idsParam = c.joined(separator: ",")
            let base = "\(baseURL)/Users/\(userId)/Items"
            var req = HTTPClientRequest(url: "\(base)?Ids=\(idsParam)&Fields=RunTimeTicks,UserData")
            req.method = .GET
            req.headers.add(name: "X-MediaBrowser-Token", value: apiKey)
            req.headers.add(name: "Accept", value: "application/json")

            let resp = try await httpClient.execute(req, timeout: .seconds(15))
            guard resp.status == .ok else {
                throw JellyfinError.httpError(resp.status.code, "Failed to fetch items batch")
            }
            let data = try await resp.body.collect(upTo: 5 * 1024 * 1024)
            let decoded = try JSONDecoder().decode(JellyfinItemsResponse.self, from: data)
            aggregated.append(contentsOf: decoded.items)
        }
        return aggregated
    }
    
    // MARK: - Server Info
    
    func getServerInfo() async throws -> JellyfinServerInfo {
        let url = "\(baseURL)/System/Info/Public"
        
        var request = HTTPClientRequest(url: url)
        request.method = .GET
        request.headers.add(name: "Accept", value: "application/json")
        
        let response = try await httpClient.execute(request, timeout: .seconds(10))
        
        guard response.status == .ok else {
            throw JellyfinError.httpError(response.status.code, "Failed to fetch server info")
        }
        
        let data = try await response.body.collect(upTo: 1024 * 1024)
        return try JSONDecoder().decode(JellyfinServerInfo.self, from: data)
    }
    
    // MARK: - Authentication Test
    
    func testConnection() async throws -> Bool {
        let url = "\(baseURL)/Users/\(userId)"
        
        var request = HTTPClientRequest(url: url)
        request.method = .GET
        request.headers.add(name: "X-MediaBrowser-Token", value: apiKey)
        request.headers.add(name: "Accept", value: "application/json")
        
        let response = try await httpClient.execute(request, timeout: .seconds(10))
        
        return response.status == .ok
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        var result: [[Element]] = []
        var idx = startIndex
        while idx < endIndex {
            let end = index(idx, offsetBy: size, limitedBy: endIndex) ?? endIndex
            result.append(Array(self[idx..<end]))
            idx = end
        }
        return result
    }
}

// MARK: - Response Types

struct JellyfinItemsResponse: Codable, Sendable {
    let items: [JellyfinMovieMetadata]
    let totalRecordCount: Int
    let startIndex: Int

    enum CodingKeys: String, CodingKey {
        case items = "Items"
        case totalRecordCount = "TotalRecordCount"
        case startIndex = "StartIndex"
    }
}

struct JellyfinServerInfo: Codable, Sendable {
    let localAddress: String
    let serverName: String
    let version: String
    let productName: String
    let operatingSystem: String
    let id: String
    let startupWizardCompleted: Bool?

    enum CodingKeys: String, CodingKey {
        case localAddress = "LocalAddress"
        case serverName = "ServerName"
        case version = "Version"
        case productName = "ProductName"
        case operatingSystem = "OperatingSystem"
        case id = "Id"
        case startupWizardCompleted = "StartupWizardCompleted"
    }
}

// MARK: - Errors

enum JellyfinError: Error, CustomStringConvertible {
    case httpError(UInt, String)
    case invalidResponse
    case authenticationFailed
    case movieNotFound(String)
    case connectionFailed
    
    var description: String {
        switch self {
        case .httpError(let code, let message):
            return "Jellyfin HTTP Error (\(code)): \(message)"
        case .invalidResponse:
            return "Invalid response from Jellyfin server"
        case .authenticationFailed:
            return "Authentication failed - check API key and user ID"
        case .movieNotFound(let id):
            return "Movie not found: \(id)"
        case .connectionFailed:
            return "Failed to connect to Jellyfin server"
        }
    }
}

// MARK: - Extensions

extension JellyfinMovieMetadata {
    func toMovie() -> Movie {
        Movie(
            jellyfinId: id,
            title: name,
            originalTitle: originalTitle,
            year: productionYear,
            overview: overview,
            runtimeMinutes: runtimeMinutes,
            genres: genres,
            director: director,
            cast: cast,
            jellyfinMetadata: self
        )
    }
}

// MARK: - Auth Response Types

struct JellyfinAuthResponse: Codable, Sendable {
    let accessToken: String
    let user: JellyfinAuthUser

    enum CodingKeys: String, CodingKey {
        case accessToken = "AccessToken"
        case user = "User"
    }
}

struct JellyfinAuthUser: Codable, Sendable {
    let id: String

    enum CodingKeys: String, CodingKey {
        case id = "Id"
    }
}
