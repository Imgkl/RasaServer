import Foundation
import Hummingbird
import HTTPTypes
import FluentKit
import Logging
import AsyncHTTPClient

final class APIRoutes: @unchecked Sendable {
    let movieService: MovieService
    let config: JellybellyConfiguration
    let logger = Logger(label: "APIRoutes")
    let httpClient: HTTPClient

    init(movieService: MovieService, config: JellybellyConfiguration, httpClient: HTTPClient) {
        self.movieService = movieService
        self.config = config
        self.httpClient = httpClient
    }
    
    func addRoutes(to router: Router<BasicRequestContext>) {
        // Health check
        router.get("/health") { _, _ in Response(status: .ok) }
        // Version endpoint
        router.get("/version") { _, _ in
            struct VersionResponse: Codable { let version: String }
            let v = ProcessInfo.processInfo.environment["JELLYBELLY_VERSION"] ?? "dev"
            return try jsonResponse(VersionResponse(version: v))
        }
        
        // API v1 routes
        let api = router.group("api/v1")
        
        // Moods endpoints
        addMoodRoutes(to: api)
        
        // Movies endpoints
        addMovieRoutes(to: api)
        
        // Tags endpoints
        addTagRoutes(to: api)
        
        // Search endpoints
        addSearchRoutes(to: api)
        
        // Sync endpoints
        addSyncRoutes(to: api)

        // Settings endpoints
        addSettingsRoutes(to: api)

        // Import/Export endpoints
        addImportExportRoutes(to: api)

        // Clients endpoints
        addClientRoutes(to: api)
    }
    
    // MARK: - Mood Routes
    
    private func addMoodRoutes(to router: RouterGroup<BasicRequestContext>) {
        let moods = router.group("moods")
        
        // GET /api/v1/moods - List all available mood buckets
        moods.get { request, context in
            try jsonResponse(MoodBucketsResponse(
                moods: self.movieService.config.moodBuckets
            ))
        }
        
        // GET /api/v1/moods/:slug - Get specific mood bucket
        moods.get(":slug") { request, context in
            let slug = try context.parameters.require("slug")
            
            guard let mood = self.movieService.config.moodBuckets[String(slug)] else {
                throw HTTPError(.notFound)
            }
            struct BucketResponse: Codable { let slug: String; let mood: MoodBucket }
            return try jsonResponse(BucketResponse(slug: String(slug), mood: mood))
        }
        
        // GET /api/v1/moods/:slug/movies - Get movies with specific mood
        moods.get(":slug/movies") { request, context in
            let slug = try context.parameters.require("slug")
            let limit = request.uri.queryParameters["limit"].flatMap { Int(String($0)) } ?? 50
            let offset = request.uri.queryParameters["offset"].flatMap { Int(String($0)) } ?? 0
            
            return try jsonResponse(try await self.movieService.getMovies(withTag: String(slug), limit: limit, offset: offset))
        }
    }
    
    // MARK: - Movie Routes
    
    private func addMovieRoutes(to router: RouterGroup<BasicRequestContext>) {
        let movies = router.group("movies")
        
        // GET /api/v1/movies - List movies with pagination
        movies.get { request, context in
            let limit = request.uri.queryParameters["limit"].flatMap { Int(String($0)) } ?? 50
            let offset = request.uri.queryParameters["offset"].flatMap { Int(String($0)) } ?? 0
            let withTags = request.uri.queryParameters["with_tags"].map { String($0) == "true" } ?? false
            
            return try jsonResponse(try await self.movieService.getMovies(limit: limit, offset: offset, includeTags: withTags))
        }
        
        // GET /api/v1/movies/:id - Get specific movie
        movies.get(":id") { request, context in
            let movieId = try context.parameters.require("id")
            return try jsonResponse(try await self.movieService.getMovie(id: String(movieId), includeTags: true))
        }
        
        // PUT /api/v1/movies/:id/tags - Update movie tags
        movies.put(":id/tags") { request, context in
            let movieId = try context.parameters.require("id")
            let updateRequest = try await request.decode(as: UpdateMovieTagsRequest.self, context: context)
            try updateRequest.validate()
            
            return try jsonResponse(try await self.movieService.updateMovieTags(
                movieId: String(movieId),
                tagSlugs: updateRequest.tagSlugs,
                replaceAll: updateRequest.replaceAll
            ))
        }
        
        // POST /api/v1/movies/:id/auto-tag - Generate automatic tags
        movies.post(":id/auto-tag") { request, context in
            let movieId = try context.parameters.require("id")
            let autoTagRequest = try await request.decode(as: AutoTagRequest.self, context: context)
            
            return try jsonResponse(try await self.movieService.generateAutoTags(
                movieId: String(movieId),
                provider: autoTagRequest.provider,
                suggestionsOnly: autoTagRequest.suggestionsOnly,
                customPrompt: autoTagRequest.customPrompt
            ))
        }
        
        // GET /api/v1/movies/:id/play - Get playback URLs
        movies.get(":id/play") { request, context in
            let movieId = try context.parameters.require("id")
            let format = request.uri.queryParameters["format"].map { String($0) } ?? "hls"
            
            return try jsonResponse(try await self.movieService.getPlaybackUrls(movieId: String(movieId), format: format))
        }
        
        // GET /api/v1/movies/:id/subtitles - Get available subtitles
        movies.get(":id/subtitles") { request, context in
            let movieId = try context.parameters.require("id")
            return try jsonResponse(try await self.movieService.getAvailableSubtitles(movieId: String(movieId)))
        }
    }
    
    // MARK: - Tag Routes
    
    private func addTagRoutes(to router: RouterGroup<BasicRequestContext>) {
        let tags = router.group("tags")
        
        // GET /api/v1/tags - List all tags with usage stats
        tags.get { request, context in
            let sortBy = request.uri.queryParameters["sort_by"].map { String($0) } ?? "usage"
            let order = request.uri.queryParameters["order"].map { String($0) } ?? "desc"
            
            return try jsonResponse(try await self.movieService.getAllTags(sortBy: sortBy, order: order))
        }
        
        // GET /api/v1/tags/:slug - Get specific tag info
        tags.get(":slug") { request, context in
            let slug = try context.parameters.require("slug")
            return try jsonResponse(try await self.movieService.getTag(slug: String(slug)))
        }
        
        // GET /api/v1/tags/:slug/movies - Get movies with specific tag
        tags.get(":slug/movies") { request, context in
            let slug = try context.parameters.require("slug")
            let limit = request.uri.queryParameters["limit"].flatMap { Int(String($0)) } ?? 50
            let offset = request.uri.queryParameters["offset"].flatMap { Int(String($0)) } ?? 0
            
            return try jsonResponse(try await self.movieService.getMovies(withTag: String(slug), limit: limit, offset: offset))
        }

        // DELETE /api/v1/tags/reset-all - Remove all tags from all movies
        tags.delete("reset-all") { request, context in
            try await self.movieService.resetAllTags()
            return try jsonResponse(["success": true])
        }
    }
    
    // MARK: - Search Routes
    
    private func addSearchRoutes(to router: RouterGroup<BasicRequestContext>) {
        let search = router.group("search")
        
        // GET /api/v1/search/movies - Search movies by title, director, etc.
        search.get("movies") { request, context in
            guard let query = request.uri.queryParameters["q"] else {
                throw HTTPError(.badRequest)
            }
            
            let limit = request.uri.queryParameters["limit"].flatMap { Int(String($0)) } ?? 20
            let includeTags = request.uri.queryParameters["with_tags"].map { String($0) == "true" } ?? false
            
            return try jsonResponse(try await self.movieService.searchMovies(
                query: String(query),
                limit: limit,
                includeTags: includeTags
            ))
        }
        
        // GET /api/v1/search/tags - Search mood tags
        search.get("tags") { request, context in
            guard let query = request.uri.queryParameters["q"] else {
                throw HTTPError(.badRequest)
            }
            
            return try jsonResponse(try await self.movieService.searchTags(query: String(query)))
        }
    }
    
    // MARK: - Sync Routes
    
    private func addSyncRoutes(to router: RouterGroup<BasicRequestContext>) {
        let sync = router.group("sync")
        
        // POST /api/v1/sync/jellyfin - Sync with Jellyfin server
        sync.post("jellyfin") { request, context in
            // Ensure runtime client uses latest saved token before syncing
            let store = SettingsStore(db: self.movieService.fluent.db(), logger: self.logger)
            try await store.ensureTable()
            if let url = try await store.get("jellyfin_url"),
               let api = try await store.get("jellyfin_api_key"),
               let uid = try await store.get("jellyfin_user_id") {
                self.movieService.reconfigureJellyfin(baseURL: url, apiKey: api, userId: uid)
            }
            let fullSync = request.uri.queryParameters["full"].map { String($0) == "true" } ?? false
            return try jsonResponse(try await self.movieService.syncWithJellyfin(fullSync: fullSync))
        }
        
        // GET /api/v1/sync/status - Get sync status
        sync.get("status") { request, context in
            return try jsonResponse(try await self.movieService.getSyncStatus())
        }
        
        // POST /api/v1/sync/test-connection - Test Jellyfin connection
        sync.post("test-connection") { request, context in
            return try jsonResponse(try await self.movieService.testJellyfinConnection())
        }
    }

    // MARK: - Import/Export Routes
    private func addImportExportRoutes(to router: RouterGroup<BasicRequestContext>) {
        let data = router.group("data")

        // GET /api/v1/data/export - Export tags map as JSON
        data.get("export") { request, context in
            let map = try await self.movieService.exportTagsMap()
            return try jsonResponse(map)
        }

        struct ImportPayload: Codable { let replaceAll: Bool?; let map: [String: ExportMovieTags] }

        // POST /api/v1/data/import - Import tags map JSON
        data.post("import") { request, context in
            let payload = try await request.decode(as: ImportPayload.self, context: context)
            try await self.movieService.importTagsMap(payload.map, replaceAll: payload.replaceAll ?? true)
            return try jsonResponse(["success": true])
        }
    }

    // MARK: - Clients Routes
    private func addClientRoutes(to router: RouterGroup<BasicRequestContext>) {
        let clients = router.group("clients")
        let movies = clients.group("movies")
        let moods = clients.group("moods")
        // GET /api/v1/clients/ping - Simple connectivity check for clients
        clients.get("ping") { request, context in
            struct ClientPingResponse: Codable { let success: Bool}
            return try jsonResponse(ClientPingResponse(success: true))
        }
        // GET /api/v1/clients/movies - Return all movies with client payload
        movies.get { request, context in
            // Return everything; include tags; no pagination as requested
            return try jsonResponse(try await self.movieService.getClientMovies())
        }

        // GET /api/v1/clients/moods - list buckets
        moods.get { request, context in
            struct ClientMoods: Codable { let moods: [String: MoodBucket] }
            return try jsonResponse(ClientMoods(moods: self.movieService.config.moodBuckets))
        }

        // GET /api/v1/clients/moods/:slug/movies - movies for mood
        moods.get(":slug/movies") { request, context in
            let slug = try context.parameters.require("slug")
            return try jsonResponse(try await self.movieService.getClientMovies(withTag: String(slug)))
        }

        // GET /api/v1/clients/timeline - movies sorted by year ascending; unknown year last
        clients.get("timeline") { request, context in
            return try jsonResponse(try await self.movieService.getClientTimeline())
        }

        // GET /api/v1/clients/home - aggregated landing payload
        clients.get("home") { request, context in
            // Parse optional header for mood exclusions
            let headerName = HTTPField.Name("X-Mood-Exclude")
            let excludeHeader = request.headers.first { $0.name == headerName }?.value
            let excludedMoods: [String] = excludeHeader.map { value in
                value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            } ?? []

            async let banner = self.movieService.getBannerMovies(maxCount: 5)
            async let cont = self.movieService.getContinueWatchingMovies()
            async let recent = self.movieService.getRecentlyAddedMovies(maxCount: 10)
            async let random = self.movieService.getRandomMoodSection(excluding: excludedMoods)
            async let progress = self.movieService.getTotalProgress()

            let (bannerItems, contItems, recentItems, randomSection, progressStats) = try await (banner, cont, recent, random, progress)

            struct RandomBlock: Codable { let mood: String; let moodTitle: String; let items: [ClientMovieResponse] }
            struct ProgressStats: Codable { let totalMovies: Int; let watchedMovies: Int; let progressPercent: Float }
            struct HomePayload: Codable {
                let banner: [ClientMovieResponse]?
                let continueWatching: [ClientMovieResponse]?
                let recentlyAdded: [ClientMovieResponse]?
                let random: RandomBlock?
                let progress: ProgressStats
            }

            let payload = HomePayload(
                banner: bannerItems.isEmpty ? nil : bannerItems,
                continueWatching: contItems.isEmpty ? nil : contItems,
                recentlyAdded: recentItems.isEmpty ? nil : recentItems,
                random: {
                    if let r = randomSection {
                        return RandomBlock(mood: r.mood, moodTitle: r.moodTitle, items: r.items)
                    } else { return nil }
                }(),
                progress: ProgressStats(
                    totalMovies: progressStats.totalMovies,
                    watchedMovies: progressStats.watchedMovies,
                    progressPercent: progressStats.progressPercent
                )
            )

            return try jsonResponse(payload)
        }

        // Playback reporting proxies
        struct StartPayload: Codable { let jellyfinId: String; let positionMs: Int?; let playMethod: String?; let audioStreamIndex: Int?; let subtitleStreamIndex: Int? }
        clients.post("playback/start") { request, context in
            let payload = try await request.decode(as: StartPayload.self, context: context)
            try await self.movieService.jellyfinService.reportPlaybackStart(
                itemId: payload.jellyfinId,
                positionMs: payload.positionMs,
                playMethod: payload.playMethod,
                audioStreamIndex: payload.audioStreamIndex,
                subtitleStreamIndex: payload.subtitleStreamIndex
            )
            return try jsonResponse(SuccessResponse(success: true))
        }

        struct ProgressPayload: Codable { let jellyfinId: String; let positionMs: Int; let isPaused: Bool? }
        clients.post("playback/progress") { request, context in
            let payload = try await request.decode(as: ProgressPayload.self, context: context)
            try await self.movieService.jellyfinService.reportPlaybackProgress(
                itemId: payload.jellyfinId,
                positionMs: payload.positionMs,
                isPaused: payload.isPaused
            )
            return try jsonResponse(SuccessResponse(success: true))
        }

        struct StopPayload: Codable { let jellyfinId: String; let positionMs: Int? }
        clients.post("playback/stop") { request, context in
            let payload = try await request.decode(as: StopPayload.self, context: context)
            try await self.movieService.jellyfinService.reportPlaybackStopped(
                itemId: payload.jellyfinId,
                positionMs: payload.positionMs
            )
            return try jsonResponse(SuccessResponse(success: true))
        }
    }
    // MARK: - Settings Routes (BYOK)
    private func addSettingsRoutes(to router: RouterGroup<BasicRequestContext>) {
        let settings = router.group("settings")

        struct KeysPayload: Codable {
            let anthropic_api_key: String?
        }

        settings.post("keys") { request, context in
            let payload = try await request.decode(as: KeysPayload.self, context: context)
            if let v = payload.anthropic_api_key { self.config.anthropicApiKey = v }
            // Persist to DB (settings table)
            let store = SettingsStore(db: self.movieService.fluent.db(), logger: self.logger)
            try await store.ensureTable()
            try await store.set("anthropic_api_key", self.config.anthropicApiKey ?? "")
            return try jsonResponse(["success": true])
        }

        // Maintenance: clear all movies
        settings.post("clear-movies") { request, context in
            try await self.movieService.clearAllMovies()
            return try jsonResponse(["success": true])
        }

        // Jellyfin config save
        struct JellyfinPayload: Codable {
            let jellyfin_url: String?
            let jellyfin_api_key: String?
            let jellyfin_user_id: String?
            let jellyfin_username: String?
            let jellyfin_password: String?
        }

        settings.post("jellyfin") { request, context in
            let payload = try await request.decode(as: JellyfinPayload.self, context: context)
            if let v = payload.jellyfin_url { self.config.jellyfinUrl = v }
            if let v = payload.jellyfin_api_key { self.config.jellyfinApiKey = v }
            if let v = payload.jellyfin_user_id { self.config.jellyfinUserId = v }
            // Save to DB (also optional creds for auto-renew)
            let store = SettingsStore(db: self.movieService.fluent.db(), logger: self.logger)
            try await store.ensureTable()
            try await store.set("jellyfin_url", self.config.jellyfinUrl)
            try await store.set("jellyfin_api_key", self.config.jellyfinApiKey)
            try await store.set("jellyfin_user_id", self.config.jellyfinUserId)
            if let u = payload.jellyfin_username { try await store.set("jellyfin_username", u) }
            if let p = payload.jellyfin_password {
                let key = try SecretsManager.loadOrCreateKey(logger: self.logger)
                let enc = try SecretsManager.encryptString(p, key: key)
                try await store.set("jellyfin_password_enc", enc)
            }
            // Reconfigure runtime client so next sync uses fresh token
            self.movieService.reconfigureJellyfin(baseURL: self.config.jellyfinUrl, apiKey: self.config.jellyfinApiKey, userId: self.config.jellyfinUserId)
            return try jsonResponse(["success": true])
        }

        struct SettingsInfo: Codable { let jellyfin_url: String; let jellyfin_api_key_set: Bool; let jellyfin_user_id: String; let anthropic_key_set: Bool }
        settings.get("info") { request, context in
            let store = SettingsStore(db: self.movieService.fluent.db(), logger: self.logger)
            try await store.ensureTable()
            let url = try await store.get("jellyfin_url") ?? self.config.jellyfinUrl
            let uid = try await store.get("jellyfin_user_id") ?? self.config.jellyfinUserId
            let api = (try await store.get("jellyfin_api_key")) ?? self.config.jellyfinApiKey
            let anth = (try await store.get("anthropic_api_key")) ?? (self.config.anthropicApiKey ?? "")
            let info = SettingsInfo(
                jellyfin_url: url,
                jellyfin_api_key_set: !api.isEmpty,
                jellyfin_user_id: uid,
                anthropic_key_set: !anth.isEmpty
            )
            return try jsonResponse(info)
        }

        // Login with username/password; optional save flag to persist to DB
        struct LoginPayload: Codable { let jellyfin_url: String; let username: String; let password: String }
        struct LoginResponse: Codable { let success: Bool; let error: String?; let userId: String?; let serverName: String?; let version: String?; let localAddress: String? }
        settings.post("login") { request, context in
            let payload = try await request.decode(as: LoginPayload.self, context: context)
            let saveFlag = request.uri.queryParameters["save"].map { String($0).lowercased() == "true" } ?? false
            do {
                let auth = try await JellyfinService.login(baseURL: payload.jellyfin_url, username: payload.username, password: payload.password, httpClient: self.httpClient)
                // Get server info
                let tmpSvc = JellyfinService(baseURL: payload.jellyfin_url, apiKey: auth.token, userId: auth.userId, httpClient: self.httpClient)
                let info = try? await tmpSvc.getServerInfo()
                if saveFlag {
                    self.config.jellyfinUrl = payload.jellyfin_url
                    self.config.jellyfinApiKey = auth.token
                    self.config.jellyfinUserId = auth.userId
                    let store = SettingsStore(db: self.movieService.fluent.db(), logger: self.logger)
                    try await store.ensureTable()
                    try await store.set("jellyfin_url", self.config.jellyfinUrl)
                    try await store.set("jellyfin_api_key", self.config.jellyfinApiKey)
                    try await store.set("jellyfin_user_id", self.config.jellyfinUserId)
                    try await store.set("jellyfin_username", payload.username)
                    let key = try SecretsManager.loadOrCreateKey(logger: self.logger)
                    let enc = try SecretsManager.encryptString(payload.password, key: key)
                    try await store.set("jellyfin_password_enc", enc)
                    // Reconfigure runtime client
                    self.movieService.reconfigureJellyfin(baseURL: self.config.jellyfinUrl, apiKey: self.config.jellyfinApiKey, userId: self.config.jellyfinUserId)
                }
                return try jsonResponse(LoginResponse(success: true, error: nil, userId: auth.userId, serverName: info?.serverName, version: info?.version, localAddress: info?.localAddress))
            } catch {
                return try jsonResponse(LoginResponse(success: false, error: error.localizedDescription, userId: nil, serverName: nil, version: nil, localAddress: nil))
            }
        }
    }
}

// MARK: - Response Types

struct MoviesListResponse: Codable, Sendable {
    let movies: [MovieResponse]
    let totalCount: Int
    let offset: Int
    let limit: Int
}

struct TagsListResponse: Codable, Sendable {
    let tags: [TagResponse]
    let totalCount: Int
}

struct PlaybackUrlsResponse: Codable, Sendable {
    let directPlayUrl: String?
    let hlsUrl: String
    let subtitleTracks: [SubtitleTrack]
    let audioTracks: [AudioTrack]
}

struct SubtitleTrack: Codable, Sendable {
    let index: Int
    let title: String?
    let language: String?
    let codec: String
    let isForced: Bool
    let isDefault: Bool
    let url: String?
}

struct AudioTrack: Codable, Sendable {
    let index: Int
    let title: String?
    let language: String?
    let codec: String
    let channels: Int?
    let isDefault: Bool
}

struct SyncStatusResponse: Codable, Sendable {
    let isRunning: Bool
    let lastSyncAt: Date?
    let lastSyncDuration: TimeInterval?
    let moviesFound: Int
    let moviesUpdated: Int
    let moviesDeleted: Int
    let errors: [String]
}

struct ConnectionTestResponse: Codable, Sendable {
    let success: Bool
    let serverInfo: JellyfinServerInfo?
    let error: String?
}

// Response types used above
struct ErrorResponse: Codable, Sendable {
    let error: String
    let message: String
    let status: Int
}
