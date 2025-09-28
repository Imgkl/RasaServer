import Foundation
import Logging
import AsyncHTTPClient
import NIOCore
import NIOHTTP1

final class JellyfinService: Sendable {
    let httpClient: HTTPClient
    private let userId: String
    let baseURL: String
    let apiKey: String
    private let deviceId: String
    private let logger = Logger(label: "JellyfinService")
    
    init(baseURL: String, apiKey: String, userId: String, httpClient: HTTPClient) {
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.apiKey = apiKey
        self.userId = userId
        self.httpClient = httpClient
        self.deviceId = "RasaServer-\(UUID().uuidString)"
    }
    
    // MARK: - Authentication (Username/Password)
    
    static func login(baseURL: String, username: String, password: String, httpClient: HTTPClient) async throws -> (token: String, userId: String) {
        let cleanBaseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let deviceId = "RasaServer-\(UUID().uuidString)"
        
        let loginData = [
            "Username": username,
            "Pw": password
        ]
        
        let jsonData = try JSONSerialization.data(withJSONObject: loginData)
        
        var request = HTTPClientRequest(url: "\(cleanBaseURL)/Users/AuthenticateByName")
        request.method = .POST
        request.headers.add(name: "Content-Type", value: "application/json")
        request.headers.add(name: "Authorization", value: "MediaBrowser Client=\"Rasa\", Device=\"RasaServer\", DeviceId=\"\(deviceId)\", Version=\"1.0.0\"")
        request.body = .bytes(ByteBuffer(data: jsonData))
        
        let response = try await httpClient.execute(request, timeout: .seconds(30))
        
        guard response.status == .ok else {
            throw JellyfinError.authenticationFailed("Login failed with status: \(response.status)")
        }
        
        let responseData = try await response.body.collect(upTo: 1024 * 1024) // 1MB limit
        let authResult = try JSONDecoder().decode(AuthenticationResult.self, from: responseData)
        
        return (token: authResult.accessToken ?? "", userId: authResult.user?.id ?? "")
    }
    
    // MARK: - Movies
    
    func fetchAllMovies() async throws -> [JellyfinMovieMetadata] {
        logger.info("Fetching movies from Jellyfin")
        
        let queryItems = [
            "Recursive": "true",
            "SortOrder": "Ascending",
            "Fields": "Overview,Genres,People,MediaStreams,ProviderIds,Studios,Taglines,RemoteTrailers",
            "IncludeItemTypes": "Movie",
            "SortBy": "SortName"
        ]
        
        let queryString = queryItems.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }.joined(separator: "&")
        
        var request = HTTPClientRequest(url: "\(baseURL)/Users/\(userId)/Items?\(queryString)")
        request.method = .GET
        request.headers.add(name: "Authorization", value: "MediaBrowser Token=\"\(apiKey)\"")
        
        let response = try await httpClient.execute(request, timeout: .seconds(60))
        
        guard response.status == .ok else {
            throw JellyfinError.requestFailed("Failed to fetch movies: \(response.status)")
        }
        
        let responseData = try await response.body.collect(upTo: 10 * 1024 * 1024) // 10MB limit
        let itemsResponse = try JSONDecoder().decode(JellyfinItemsResponse.self, from: responseData)
        let items = itemsResponse.items ?? []
        
        logger.info("Fetched \(items.count) movies from Jellyfin")
        return items.map { $0.toJellyfinMovieMetadata() }
    }

    func getSimilarMovies(to movieId: String, limit: Int = 10) async throws -> [JellyfinMovieMetadata] {
        let queryItems = [
            "Limit": "\(limit)",
            "Fields": "UserData,RunTimeTicks"
        ]
        
        let queryString = queryItems.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }.joined(separator: "&")
        
        var request = HTTPClientRequest(url: "\(baseURL)/Items/\(movieId)/Similar?\(queryString)")
        request.method = .GET
        request.headers.add(name: "Authorization", value: "MediaBrowser Token=\"\(apiKey)\"")
        
        let response = try await httpClient.execute(request, timeout: .seconds(30))
        
        guard response.status == .ok else {
            throw JellyfinError.requestFailed("Failed to fetch similar movies: \(response.status)")
        }
        
        let responseData = try await response.body.collect(upTo: 5 * 1024 * 1024) // 5MB limit
        let itemsResponse = try JSONDecoder().decode(JellyfinItemsResponse.self, from: responseData)
        return (itemsResponse.items ?? []).map { $0.toJellyfinMovieMetadata() }
    }

    func getResumeItems(limit: Int = 10) async throws -> [JellyfinMovieMetadata] {
        let queryItems = [
            "Limit": "\(limit)",
            "Fields": "UserData,RunTimeTicks",
            "IncludeItemTypes": "Movie"
        ]
        
        let queryString = queryItems.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }.joined(separator: "&")
        
        var request = HTTPClientRequest(url: "\(baseURL)/Users/\(userId)/Items/Resume?\(queryString)")
        request.method = .GET
        request.headers.add(name: "Authorization", value: "MediaBrowser Token=\"\(apiKey)\"")
        
        let response = try await httpClient.execute(request, timeout: .seconds(30))
        
        guard response.status == .ok else {
            throw JellyfinError.requestFailed("Failed to fetch resume items: \(response.status)")
        }
        
        let responseData = try await response.body.collect(upTo: 5 * 1024 * 1024) // 5MB limit
        let itemsResponse = try JSONDecoder().decode(JellyfinItemsResponse.self, from: responseData)
        return (itemsResponse.items ?? []).map { $0.toJellyfinMovieMetadata() }
    }

    func getRecentlyAddedMovies(limit: Int = 20) async throws -> [JellyfinMovieMetadata] {
        let queryItems = [
            "Limit": "\(limit)",
            "Recursive": "true",
            "SortOrder": "Descending",
            "Fields": "UserData,RunTimeTicks",
            "IncludeItemTypes": "Movie",
            "SortBy": "DateCreated"
        ]
        
        let queryString = queryItems.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }.joined(separator: "&")
        
        var request = HTTPClientRequest(url: "\(baseURL)/Users/\(userId)/Items?\(queryString)")
        request.method = .GET
        request.headers.add(name: "Authorization", value: "MediaBrowser Token=\"\(apiKey)\"")
        
        let response = try await httpClient.execute(request, timeout: .seconds(30))
        
        guard response.status == .ok else {
            throw JellyfinError.requestFailed("Failed to fetch recently added movies: \(response.status)")
        }
        
        let responseData = try await response.body.collect(upTo: 5 * 1024 * 1024) // 5MB limit
        let itemsResponse = try JSONDecoder().decode(JellyfinItemsResponse.self, from: responseData)
        return (itemsResponse.items ?? []).map { $0.toJellyfinMovieMetadata() }
    }
    
    func fetchMovie(id: String) async throws -> BaseItemDto {
        var request = HTTPClientRequest(url: "\(baseURL)/Users/\(userId)/Items/\(id)?Fields=Overview,People,MediaStreams,ProviderIds,RemoteTrailers")
        request.method = .GET
        request.headers.add(name: "Authorization", value: "MediaBrowser Token=\"\(apiKey)\"")
        
        let response = try await httpClient.execute(request, timeout: .seconds(30))
        
        guard response.status == .ok else {
            throw JellyfinError.requestFailed("Failed to fetch movie: \(response.status)")
        }
        
        let responseData = try await response.body.collect(upTo: 1024 * 1024) // 1MB limit
        return try JSONDecoder().decode(BaseItemDto.self, from: responseData)
    }
    
    // MARK: - Images
    
    func getImageUrl(for item: BaseItemDto, imageType: ImageType, quality: Int = 85) -> String? {
        let availableTags = item.imageTags?.keys.joined(separator: ", ") ?? "none"
        let backdropCount = item.backdropImageTags?.count ?? 0
        logger.info("Checking \(imageType.rawValue) image for \(item.name ?? "unknown"). Available imageTags: \(availableTags), Backdrop count: \(backdropCount)")
        
        if imageType == .backdrop {
            guard let backdropTags = item.backdropImageTags,
                  !backdropTags.isEmpty else {
                logger.info("No backdrop images found for \(item.name ?? "unknown")")
                return nil
            }
            
            let url = "\(baseURL)/Items/\(item.id ?? "")/Images/Backdrop/0?quality=\(quality)&api_key=\(apiKey)"
            logger.info("Generated backdrop URL for \(item.name ?? "unknown"): \(url)")
            return url
        }
        
        guard let imageTags = item.imageTags,
              imageTags[imageType.rawValue] != nil else {
            logger.info("No \(imageType.rawValue) image found for \(item.name ?? "unknown")")
            return nil
        }
        
        let url = "\(baseURL)/Items/\(item.id ?? "")/Images/\(imageType.rawValue)?quality=\(quality)&api_key=\(apiKey)"
        logger.info("Generated \(imageType.rawValue) URL for \(item.name ?? "unknown"): \(url)")
        return url
    }
    
    // MARK: - People Images
    /// Build a person's primary image URL from id + primaryImageTag.
    /// Returns nil if tag is missing.
    func getPersonImageUrl(personId: String?, primaryImageTag: String?, quality: Int = 100) -> String? {
        guard let pid = personId, let tag = primaryImageTag, !pid.isEmpty, !tag.isEmpty else { return nil }
        return "\(baseURL)/Items/\(pid)/Images/Primary?quality=\(quality)&tag=\(tag)&api_key=\(apiKey)"
    }

    /// Build ordered list of candidate URLs for a person's image, for robust fallback.
    func buildPersonImageCandidates(personId: String?, personName: String?, primaryImageTag: String?, quality: Int = 100) -> [String] {
        var urls: [String] = []
        if let pid = personId, let tag = primaryImageTag, !pid.isEmpty, !tag.isEmpty {
            urls.append("\(baseURL)/Items/\(pid)/Images/Primary?quality=\(quality)&tag=\(tag)&api_key=\(apiKey)")
            urls.append("\(baseURL)/Persons/\(pid)/Images/Primary?quality=\(quality)&tag=\(tag)&api_key=\(apiKey)")
        }
        if let pid = personId, !pid.isEmpty {
            urls.append("\(baseURL)/Items/\(pid)/Images/Primary?quality=\(quality)&api_key=\(apiKey)")
        }
        if let name = personName, !name.isEmpty {
            let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
            urls.append("\(baseURL)/Persons/\(encoded)/Images/Primary?quality=\(quality)&api_key=\(apiKey)")
        }
        return urls
    }
    
    // MARK: - Streaming URLs
    
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
    
    
    
    // MARK: - Playback Reporting
    
    func reportPlaybackStart(itemId: String, playSessionId: String, positionMs: Int?, playMethod: String?, audioStreamIndex: Int?, subtitleStreamIndex: Int?) async throws {
        let positionTicks: Int64? = positionMs.map { Int64($0 * 10_000_000) }
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
        
        let jsonData = try JSONEncoder().encode(startInfo)
        
        var request = HTTPClientRequest(url: "\(baseURL)/Sessions/Playing/Start")
        request.method = .POST
        request.headers.add(name: "Content-Type", value: "application/json")
        request.headers.add(name: "Authorization", value: "MediaBrowser Token=\"\(apiKey)\"")
        request.body = .bytes(ByteBuffer(data: jsonData))
        
        let response = try await httpClient.execute(request, timeout: .seconds(30))
        
        guard response.status == .noContent || response.status == .ok else {
            throw JellyfinError.requestFailed("Failed to report playback start: \(response.status)")
        }
    }

    func reportPlaybackProgress(itemId: String, playSessionId: String, positionMs: Int, isPaused: Bool?) async throws {
        let positionTicks = positionMs * 10_000_000
        
        let progressInfo = PlaybackProgressInfo(
            isPaused: isPaused ?? false,
            itemID: itemId,
            mediaSourceID: itemId,
            playSessionID: playSessionId,
            positionTicks: Int64(positionTicks),
            sessionID: playSessionId
        )
        
        let jsonData = try JSONEncoder().encode(progressInfo)
        
        var request = HTTPClientRequest(url: "\(baseURL)/Sessions/Playing/Progress")
        request.method = .POST
        request.headers.add(name: "Content-Type", value: "application/json")
        request.headers.add(name: "Authorization", value: "MediaBrowser Token=\"\(apiKey)\"")
        request.body = .bytes(ByteBuffer(data: jsonData))
        
        let response = try await httpClient.execute(request, timeout: .seconds(30))
        
        guard response.status == .noContent || response.status == .ok else {
            throw JellyfinError.requestFailed("Failed to report playback progress: \(response.status)")
        }
    }

    func reportPlaybackStopped(itemId: String, playSessionId: String, positionMs: Int?) async throws {
        let positionTicks: Int? = positionMs.map { $0 * 10_000_000 }
        
        let stopInfo = PlaybackStopInfo(
            itemID: itemId,
            mediaSourceID: itemId,
            playSessionID: playSessionId,
            positionTicks: positionTicks.map { Int64($0) },
            sessionID: playSessionId
        )
        
        let jsonData = try JSONEncoder().encode(stopInfo)
        
        var request = HTTPClientRequest(url: "\(baseURL)/Sessions/Playing/Stopped")
        request.method = .POST
        request.headers.add(name: "Content-Type", value: "application/json")
        request.headers.add(name: "Authorization", value: "MediaBrowser Token=\"\(apiKey)\"")
        request.body = .bytes(ByteBuffer(data: jsonData))
        
        let response = try await httpClient.execute(request, timeout: .seconds(30))
        
        guard response.status == .noContent || response.status == .ok else {
            throw JellyfinError.requestFailed("Failed to report playback stopped: \(response.status)")
        }
    }

    // MARK: - Watched State
    func markItemPlayed(itemId: String) async throws {
        var request = HTTPClientRequest(url: "\(baseURL)/Users/\(userId)/PlayedItems/\(itemId)")
        request.method = .POST
        request.headers.add(name: "Authorization", value: "MediaBrowser Token=\"\(apiKey)\"")
        
        let response = try await httpClient.execute(request, timeout: .seconds(30))
        
        guard response.status == .ok || response.status == .noContent else {
            throw JellyfinError.requestFailed("Failed to mark item played: \(response.status)")
        }
    }

    func markItemUnplayed(itemId: String) async throws {
        var request = HTTPClientRequest(url: "\(baseURL)/Users/\(userId)/PlayedItems/\(itemId)")
        request.method = .DELETE
        request.headers.add(name: "Authorization", value: "MediaBrowser Token=\"\(apiKey)\"")
        
        let response = try await httpClient.execute(request, timeout: .seconds(30))
        
        guard response.status == .ok || response.status == .noContent else {
            throw JellyfinError.requestFailed("Failed to mark item unplayed: \(response.status)")
        }
    }

    // MARK: - Bulk item fetch
    func fetchItems(ids: [String]) async throws -> [JellyfinMovieMetadata] {
        guard !ids.isEmpty else { return [] }
        let chunks = ids.chunked(into: 80)
        var aggregated: [BaseItemDto] = []
        aggregated.reserveCapacity(ids.count)

        for c in chunks {
            let idsParam = c.joined(separator: ",")
            let queryItems = [
                "Ids": idsParam,
                "Fields": "UserData,RunTimeTicks"
            ]
            
            let queryString = queryItems.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }.joined(separator: "&")
            
            var request = HTTPClientRequest(url: "\(baseURL)/Users/\(userId)/Items?\(queryString)")
            request.method = .GET
            request.headers.add(name: "Authorization", value: "MediaBrowser Token=\"\(apiKey)\"")
            
            let response = try await httpClient.execute(request, timeout: .seconds(30))
            
            guard response.status == .ok else {
                throw JellyfinError.requestFailed("Failed to fetch items: \(response.status)")
            }
            
            let responseData = try await response.body.collect(upTo: 5 * 1024 * 1024) // 5MB limit
            let itemsResponse = try JSONDecoder().decode(JellyfinItemsResponse.self, from: responseData)
            aggregated.append(contentsOf: itemsResponse.items ?? [])
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
            throw JellyfinError.requestFailed("Failed to fetch server info: \(response.status)")
        }
        
        let data = try await response.body.collect(upTo: 1024 * 1024)
        return try JSONDecoder().decode(JellyfinServerInfo.self, from: data)
    }
    
    func testConnection() async throws -> Bool {
        let url = "\(baseURL)/Users/\(userId)"
        
        var request = HTTPClientRequest(url: url)
        request.method = .GET
        request.headers.add(name: "Authorization", value: "MediaBrowser Token=\"\(apiKey)\"")
        
        let response = try await httpClient.execute(request, timeout: .seconds(10))
        return response.status == .ok
    }
}

// MARK: - Extensions

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
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

extension BaseItemDto {
    func toJellyfinMovieMetadata() -> JellyfinMovieMetadata {
        JellyfinMovieMetadata(
            id: id ?? "",
            name: name ?? "",
            originalTitle: originalTitle,
            overview: overview,
            productionYear: productionYear,
            runTimeTicks: runTimeTicks,
            genres: genres ?? [],
            people: (people ?? []).map { person in
                JellyfinPerson(
                    name: person.name ?? "",
                    id: person.id ?? "",
                    role: person.role,
                    type: person.type ?? "",
                    primaryImageTag: person.primaryImageTag
                )
            },
            mediaStreams: (mediaStreams ?? []).map { stream in
                JellyfinMediaStream(
                    codec: stream.codec,
                    type: stream.type ?? "",
                    index: stream.index ?? 0,
                    title: stream.title,
                    language: stream.language,
                    isForced: stream.isForced ?? false,
                    isDefault: stream.isDefault ?? false
                )
            },
            providerIds: providerIds,
            studios: (studios ?? []).map { studio in
                JellyfinStudio(id: studio.id ?? "", name: studio.name ?? "")
            },
            imageBlurHashes: nil,
            userData: userData.map { userData in
                JellyfinUserData(
                    played: userData.played ?? false,
                    playbackPositionTicks: userData.playbackPositionTicks ?? 0,
                    playCount: userData.playCount ?? 0,
                    isFavorite: userData.isFavorite ?? false,
                    lastPlayedDate: userData.lastPlayedDate
                )
            },
            remoteTrailers: remoteTrailers,
            dateCreated: self.dateCreated.flatMap(Date.from(iso8601:))
        )
    }
    
    func toMovie() -> Movie {
        let metadata = toJellyfinMovieMetadata()
        return Movie(
            jellyfinId: id ?? "",
            title: name ?? "",
            originalTitle: originalTitle,
            year: productionYear,
            overview: overview,
            runtimeMinutes: runTimeTicks.map { Int($0 / 600_000_000) },
            genres: genres ?? [],
            director: people?.first(where: { $0.type == "Director" })?.name,
            cast: people?.filter { $0.type == "Actor" }.compactMap { $0.name } ?? [],
            posterUrl: nil,
            backdropUrl: nil,
            logoUrl: nil,
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
            runtimeMinutes: runTimeTicks.map { Int($0 / 600_000_000) },
            genres: genres,
            director: people.first(where: { $0.type == "Director" })?.name,
            cast: people.filter { $0.type == "Actor" }.map { $0.name },
            posterUrl: nil,
            backdropUrl: nil,
            logoUrl: nil,
            jellyfinMetadata: self
        )
    }
    
    func getImageUrl(baseURL: String, apiKey: String, imageType: ImageType, quality: Int = 85) -> String? {
        return "\(baseURL)/Items/\(id)/Images/\(imageType.rawValue)?quality=\(quality)&api_key=\(apiKey)"
    }
}
