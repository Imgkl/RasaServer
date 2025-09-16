import Foundation
@preconcurrency import JellyfinAPI
import Logging
import AsyncHTTPClient

final class JellyfinService: Sendable {
    nonisolated let client: JellyfinClient
    let httpClient: HTTPClient
    private let userId: String
    let baseURL: String
    let apiKey: String
    private let logger = Logger(label: "JellyfinService")
    
    init(baseURL: String, apiKey: String, userId: String, httpClient: HTTPClient) {
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.apiKey = apiKey
        self.userId = userId
        self.httpClient = httpClient
        
        let config = JellyfinClient.Configuration(
            url: URL(string: self.baseURL)!,
            client: "Rasa",
            deviceName: "RasaServer",
            deviceID: "RasaServer-\(UUID().uuidString)",
            version: "1.0.0"
        )
        
        // Configure URLSession with longer timeouts for large libraries
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 60.0  // 60 seconds per request
        sessionConfig.timeoutIntervalForResource = 300.0 // 5 minutes total
        
        self.client = JellyfinClient(
            configuration: config, 
            sessionConfiguration: sessionConfig,
            accessToken: apiKey
        )
    }
    
    
    // MARK: - Authentication (Username/Password)
    
    static func login(baseURL: String, username: String, password: String, httpClient: HTTPClient) async throws -> (token: String, userId: String) {
        let config = JellyfinClient.Configuration(
            url: URL(string: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")))!,
            client: "Rasa",
            deviceName: "RasaServer",
            deviceID: "RasaServer-\(UUID().uuidString)",
            version: "1.0.0"
        )
        
        // Configure URLSession with longer timeouts
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 30.0  // 30 seconds for login
        sessionConfig.timeoutIntervalForResource = 60.0  // 1 minute total
        
        let tempClient = JellyfinClient(configuration: config, sessionConfiguration: sessionConfig)
        
        let response = try await tempClient.signIn(
            username: username,
            password: password
        )
        
        return (token: response.accessToken ?? "", userId: response.user?.id ?? "")
    }
    
    // MARK: - Movies
    
    func fetchAllMovies() async throws -> [JellyfinMovieMetadata] {
        logger.info("Fetching movies from Jellyfin")
        
        let parameters = Paths.GetItemsParameters(
            userID: userId,
            isRecursive: true,
            sortOrder: [.ascending],
            fields: [.overview, .genres, .people, .mediaStreams, .providerIDs, .studios, .taglines],
            includeItemTypes: [.movie],
            sortBy: [.sortName]
        )
        
        let request = Paths.getItems(parameters: parameters)
        let response = try await client.send(request)
        let items = response.value.items ?? []
        
        logger.info("Fetched \(items.count) movies from Jellyfin")
        return items.map { $0.toJellyfinMovieMetadata() }
    }

    /// Fetch items similar to a given item from Jellyfin (movies only)
    func getSimilarMovies(to movieId: String, limit: Int = 10) async throws -> [JellyfinMovieMetadata] {
        let parameters = Paths.GetSimilarItemsParameters(
            userID: userId,
            limit: limit,
            fields: [.overview, .genres, .people, .mediaStreams, .providerIDs, .studios]
        )
        
        let request = Paths.getSimilarItems(itemID: movieId, parameters: parameters)
        let response = try await client.send(request)
        return (response.value.items ?? []).map { $0.toJellyfinMovieMetadata() }
    }

    // Fetch resume/continue-watching items for the user (movies only)
    func getResumeItems(limit: Int = 10) async throws -> [JellyfinMovieMetadata] {
        let parameters = Paths.GetResumeItemsParameters(
            userID: userId,
            limit: limit,
            fields: [.overview, .genres, .people, .mediaStreams, .providerIDs, .studios],
            includeItemTypes: [.movie]
        )
        
        let request = Paths.getResumeItems(parameters: parameters)
        let response = try await client.send(request)
        return (response.value.items ?? []).map { $0.toJellyfinMovieMetadata() }
    }


    /// Fetch recently added movies for the user, sorted by DateCreated desc
    func getRecentlyAddedMovies(limit: Int = 20) async throws -> [JellyfinMovieMetadata] {
        let parameters = Paths.GetItemsParameters(
            userID: userId,
            limit: limit,
            isRecursive: true,
            sortOrder: [.descending],
            fields: [.overview, .genres, .people, .mediaStreams, .providerIDs, .studios],
            includeItemTypes: [.movie],
            sortBy: [.dateCreated]
        )
        
        let request = Paths.getItems(parameters: parameters)
        let response = try await client.send(request)
        return (response.value.items ?? []).map { $0.toJellyfinMovieMetadata() }
    }
    
    func fetchMovie(id: String) async throws -> BaseItemDto {
        let request = Paths.getItem(itemID: id, userID: userId)
        let response = try await client.send(request)
        return response.value
    }
    
    // MARK: - Images
    
    /// Get image URL only if the image exists in BaseItemDto
    func getImageUrl(for item: BaseItemDto, imageType: JellyfinAPI.ImageType, quality: Int = 85) -> String? {
        // Log what imageTags are available
        let availableTags = item.imageTags?.keys.joined(separator: ", ") ?? "none"
        let backdropCount = item.backdropImageTags?.count ?? 0
        logger.info("Checking \(imageType.rawValue) image for \(item.name ?? "unknown"). Available imageTags: \(availableTags), Backdrop count: \(backdropCount)")
        
        // Special handling for backdrop images - they use BackdropImageTags array
        if imageType == .backdrop {
            guard let backdropTags = item.backdropImageTags,
                  !backdropTags.isEmpty else {
                logger.info("No backdrop images found for \(item.name ?? "unknown")")
                return nil
            }
            
            // Use the first backdrop image (index 0)
            let url = "\(baseURL)/Items/\(item.id ?? "")/Images/Backdrop/0?quality=\(quality)&api_key=\(apiKey)"
            logger.info("Generated backdrop URL for \(item.name ?? "unknown"): \(url)")
            return url
        }
        
        // Check if the image exists using imageTags from SDK for other image types
        guard let imageTags = item.imageTags,
              imageTags[imageType.rawValue] != nil else {
            logger.info("No \(imageType.rawValue) image found for \(item.name ?? "unknown")")
            return nil
        }
        
        let url = "\(baseURL)/Items/\(item.id ?? "")/Images/\(imageType.rawValue)?quality=\(quality)&api_key=\(apiKey)"
        logger.info("Generated \(imageType.rawValue) URL for \(item.name ?? "unknown"): \(url)")
        return url
    }
    
    
    

    
    // MARK: - Playback
    
    /// Get direct stream URL with all streaming parameters (no transcoding)
    func getStreamUrl(itemId: String, playSessionId: String, startPositionTicks: Int64? = nil, audioStreamIndex: Int? = nil, subtitleStreamIndex: Int? = nil) -> String {
        var components = URLComponents(string: "\(baseURL)/Videos/\(itemId)/stream")!
        
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "Static", value: "true"),
            URLQueryItem(name: "MediaSourceId", value: itemId),
            URLQueryItem(name: "DeviceId", value: "RasaServer"),
            URLQueryItem(name: "PlaySessionId", value: playSessionId),
            URLQueryItem(name: "api_key", value: apiKey)
        ]
        
        // Add audio stream index if specified
        if let audioIndex = audioStreamIndex {
            queryItems.append(URLQueryItem(name: "AudioStreamIndex", value: String(audioIndex)))
        }
        
        // Add subtitle stream index if specified  
        if let subtitleIndex = subtitleStreamIndex {
            queryItems.append(URLQueryItem(name: "SubtitleStreamIndex", value: String(subtitleIndex)))
        }
        
        if let startTicks = startPositionTicks {
            queryItems.append(URLQueryItem(name: "StartTimeTicks", value: String(startTicks)))
        }
        
        components.queryItems = queryItems
        return components.url?.absoluteString ?? ""
    }
    
    
    
    // MARK: - Playback Progress
    func reportPlaybackStart(itemId: String, playSessionId: String, positionMs: Int?, playMethod: String?, audioStreamIndex: Int?, subtitleStreamIndex: Int?) async throws {
        let positionTicks: Int? = positionMs.map { $0 * 10_000_000 }
        let playMethodEnum: PlayMethod? = playMethod.flatMap { PlayMethod(rawValue: $0) }
        
        let startInfo = PlaybackStartInfo(
            audioStreamIndex: audioStreamIndex,
            canSeek: true,
            itemID: itemId,
            mediaSourceID: itemId,
            playMethod: playMethodEnum,
            playSessionID: playSessionId,
            positionTicks: positionTicks,
            sessionID: playSessionId,
            subtitleStreamIndex: subtitleStreamIndex
        )
        
        let request = Paths.reportPlaybackStart(startInfo)
        _ = try await client.send(request)
    }

    func reportPlaybackProgress(itemId: String, playSessionId: String, positionMs: Int, isPaused: Bool?) async throws {
        let positionTicks = positionMs * 10_000_000
        
        let progressInfo = PlaybackProgressInfo(
            isPaused: isPaused ?? false,
            itemID: itemId,
            mediaSourceID: itemId,
            playSessionID: playSessionId,
            positionTicks: positionTicks,
            sessionID: playSessionId
        )
        
        let request = Paths.reportPlaybackProgress(progressInfo)
        _ = try await client.send(request)
    }

    func reportPlaybackStopped(itemId: String, playSessionId: String, positionMs: Int?) async throws {
        let positionTicks: Int? = positionMs.map { $0 * 10_000_000 }
        
        let stopInfo = PlaybackStopInfo(
            itemID: itemId,
            mediaSourceID: itemId,
            playSessionID: playSessionId,
            positionTicks: positionTicks,
            sessionID: playSessionId
        )
        
        let request = Paths.reportPlaybackStopped(stopInfo)
        _ = try await client.send(request)
    }

    // MARK: - Watched State
    func markItemPlayed(itemId: String) async throws {
        let request = Paths.markPlayedItem(itemID: itemId, userID: userId)
        _ = try await client.send(request)
    }

    func markItemUnplayed(itemId: String) async throws {
        let request = Paths.markUnplayedItem(itemID: itemId, userID: userId)
        _ = try await client.send(request)
    }

    // MARK: - Bulk item fetch (UserData + RunTimeTicks)
    func fetchItems(ids: [String]) async throws -> [JellyfinMovieMetadata] {
        guard !ids.isEmpty else { return [] }
        let chunks = ids.chunked(into: 80)
        var aggregated: [BaseItemDto] = []
        aggregated.reserveCapacity(ids.count)

        for c in chunks {
            let parameters = Paths.GetItemsParameters(
                userID: userId,
                ids: c
            )
            
            let request = Paths.getItems(parameters: parameters)
            let response = try await client.send(request)
            aggregated.append(contentsOf: response.value.items ?? [])
        }
        return aggregated.map { $0.toJellyfinMovieMetadata() }
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
    case noMediaSource
    case movieNotFound(String)
    case connectionFailed
    
    var description: String {
        switch self {
        case .httpError(let code, let message):
            return "Jellyfin HTTP Error (\(code)): \(message)"
        case .invalidResponse:
            return "Invalid response from Jellyfin server"
        case .authenticationFailed:
            return "Authentication failed with Jellyfin server"
        case .noMediaSource:
            return "No media source available for playback"
        case .movieNotFound(let id):
            return "Movie not found: \(id)"
        case .connectionFailed:
            return "Failed to connect to Jellyfin server"
        }
    }
}

// MARK: - Extensions

extension BaseItemDto {
    func toJellyfinMovieMetadata() -> JellyfinMovieMetadata {
        JellyfinMovieMetadata(
            id: id ?? "",
            name: name ?? "",
            originalTitle: originalTitle,
            overview: overview,
            productionYear: productionYear,
            runTimeTicks: runTimeTicks.map { Int64($0) },
            genres: genres ?? [],
            people: (people ?? []).map { person in
                JellyfinPerson(
                    name: person.name ?? "",
                    id: person.id ?? "",
                    role: person.role,
                    type: person.type?.rawValue ?? ""
                )
            },
            mediaStreams: (mediaSources?.first?.mediaStreams ?? []).map { stream in
                JellyfinMediaStream(
                    codec: stream.codec,
                    type: stream.type?.rawValue ?? "",
                    index: stream.index ?? 0,
                    title: stream.title,
                    language: stream.language,
                    isForced: stream.isForced ?? false,
                    isDefault: stream.isDefault ?? false
                )
            },
            providerIds: providerIDs,
            studios: (studios ?? []).map { studio in
                JellyfinStudio(id: studio.id ?? "", name: studio.name ?? "")
            },
            imageBlurHashes: nil,
            userData: userData.map { data in
                JellyfinUserData(
                    played: (data.playCount ?? 0) > 0,
                    playbackPositionTicks: Int64(data.playbackPositionTicks ?? 0),
                    playCount: data.playCount ?? 0,
                    isFavorite: data.isFavorite ?? false,
                    lastPlayedDate: nil
                )
            }
        )
    }
    
    /// Get image URL only if the image exists
    func getImageUrl(baseURL: String, apiKey: String, imageType: JellyfinAPI.ImageType, quality: Int = 85) -> String? {
        guard let imageTags = imageTags,
              imageTags[imageType.rawValue] != nil else {
            return nil
        }
        
        return "\(baseURL)/Items/\(id ?? "")/Images/\(imageType.rawValue)?quality=\(quality)&api_key=\(apiKey)"
    }
    
    func toMovie() -> Movie {
        let metadata = toJellyfinMovieMetadata()
        return Movie(
            jellyfinId: id ?? "",
            title: name ?? "",
            originalTitle: originalTitle,
            year: productionYear,
            overview: overview,
            runtimeMinutes: metadata.runtimeMinutes,
            genres: genres ?? [],
            director: metadata.director,
            cast: metadata.cast,
            jellyfinMetadata: metadata
        )
    }
}

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
