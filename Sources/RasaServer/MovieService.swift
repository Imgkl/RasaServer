import AsyncHTTPClient
import FluentKit
import Foundation
import HummingbirdFluent
import Logging
@preconcurrency import JellyfinAPI

final class MovieService {
  let config: RasaConfiguration
  let fluent: Fluent
  var jellyfinService: JellyfinService
  let llmService: LLMService
  private let logger = Logger(label: "MovieService")

  // Sync status tracking
  private var isSyncing = false
  private var lastSyncAt: Date?
  private var lastSyncDuration: TimeInterval?
  private var lastSyncStats = SyncStats()
  
  // Banner movies tracking to reduce repetition
  private var recentBannerMovies: [String] = []
  private let maxRecentBannerCount = 20

  init(
    config: RasaConfiguration,
    fluent: Fluent,
    jellyfinService: JellyfinService,
    llmService: LLMService
  ) {
    self.config = config
    self.fluent = fluent
    self.jellyfinService = jellyfinService
    self.llmService = llmService
  }

  // MARK: - Movie Management

  func getMovies(limit: Int = 50, offset: Int = 0, includeTags: Bool = false) async throws
    -> MoviesListResponse
  {
    let query = Movie.query(on: fluent.db())
      .sort(\.$title)
      .range(offset..<(offset + limit))

    if includeTags {
      query.with(\.$tags)
    }

    let movies = try await query.all()
    let totalCount = try await Movie.query(on: fluent.db()).count()

    let movieResponses = movies.map { movie in
      MovieResponse(movie: movie, tags: includeTags ? movie.tags : [])
    }

    return MoviesListResponse(
      movies: movieResponses,
      totalCount: totalCount,
      offset: offset,
      limit: limit
    )
  }

  // MARK: - Reconfigure Jellyfin at runtime
  func reconfigureJellyfin(baseURL: String, apiKey: String, userId: String) {
    // Reuse the shared HTTP client from existing service to avoid leaks
    let httpClient = self.jellyfinService.httpClient
    self.jellyfinService = JellyfinService(
      baseURL: baseURL, apiKey: apiKey, userId: userId, httpClient: httpClient)
    logger.info("Jellyfin service reconfigured at runtime")
  }

  // Try to re-login using stored username/password (if provided via settings/login previously)
  private func attemptAutoLoginAndUpdate() async throws -> Bool {
    // Load creds from DB settings (if present)
    let store = SettingsStore(db: fluent.db(), logger: logger)
    try await store.ensureTable()
    guard let url = try await store.get("jellyfin_url"),
      let username = try await store.get("jellyfin_username"),
      let encPwd = try await store.get("jellyfin_password_enc")
    else {
      return false
    }
    // Decrypt password
    let key = try SecretsManager.loadOrCreateKey(logger: logger)
    let password = try SecretsManager.decryptString(encPwd, key: key)
    // Login using shared client
    let httpClient = self.jellyfinService.httpClient
    do {
      let auth = try await JellyfinService.login(
        baseURL: url, username: username, password: password, httpClient: httpClient)
      // Save new token
      try await store.set("jellyfin_api_key", auth.token)
      try await store.set("jellyfin_user_id", auth.userId)
      // Update in-memory
      reconfigureJellyfin(baseURL: url, apiKey: auth.token, userId: auth.userId)
      return true
    } catch {
      logger.error("Auto-login failed: \(error)")
      return false
    }
  }

  func getMovie(id: String, includeTags: Bool = false) async throws -> MovieResponse {
    // Try UUID first, then Jellyfin ID
    let movie: Movie
    if let uuid = UUID(uuidString: id) {
      movie = try await Movie.query(on: fluent.db())
        .filter(\.$id == uuid)
        .with(\.$tags)
        .first()
        .unwrap(orError: MovieServiceError.movieNotFound(id))
    } else {
      movie = try await Movie.query(on: fluent.db())
        .filter(\.$jellyfinId == id)
        .with(\.$tags)
        .first()
        .unwrap(orError: MovieServiceError.movieNotFound(id))
    }

    return MovieResponse(movie: movie, tags: includeTags ? movie.tags : [])
  }

  func getMovies(withTag tagSlug: String, limit: Int = 50, offset: Int = 0) async throws
    -> MoviesListResponse
  {
    // Check if tag exists (aliases removed)
    guard config.moodBuckets[tagSlug] != nil else {
      throw MovieServiceError.tagNotFound(tagSlug)
    }

    let tag = try await Tag.query(on: fluent.db())
      .filter(\.$slug == tagSlug)
      .first()
      .unwrap(orError: MovieServiceError.tagNotFound(tagSlug))

    let movies = try await Movie.query(on: fluent.db())
      .join(MovieTag.self, on: \Movie.$id == \MovieTag.$movie.$id)
      .filter(MovieTag.self, \.$tag.$id == tag.requireID())
      .with(\.$tags)
      .sort(\.$title)
      .range(offset..<(offset + limit))
      .all()

    let totalCount = try await Movie.query(on: fluent.db())
      .join(MovieTag.self, on: \Movie.$id == \MovieTag.$movie.$id)
      .filter(MovieTag.self, \.$tag.$id == tag.requireID())
      .count()

    let movieResponses = movies.map { MovieResponse(movie: $0, tags: $0.tags) }

    return MoviesListResponse(
      movies: movieResponses,
      totalCount: totalCount,
      offset: offset,
      limit: limit
    )
  }

  // MARK: - Tag Management

  func updateMovieTags(movieId: String, tagSlugs: [String], replaceAll: Bool) async throws
    -> MovieResponse
  {
    let movie = try await getMovieEntity(id: movieId)

    // Validate tag slugs
    let validSlugs = try validateTagSlugs(tagSlugs)

    if replaceAll {
      // Remove all existing tags
      try await MovieTag.query(on: fluent.db())
        .filter(\.$movie.$id == movie.requireID())
        .delete()
    }

    // Get or create tags
    var tags: [Tag] = []
    for slug in validSlugs {
      let tag = try await getOrCreateTag(slug: slug)
      tags.append(tag)
    }

    if replaceAll {
      // Add new tags
      for tag in tags {
        let movieTag = MovieTag(
          movieId: try movie.requireID(),
          tagId: try tag.requireID(),
          addedByAutoTag: false
        )
        try await movieTag.save(on: fluent.db())
      }
    } else {
      // Add only new tags (check for duplicates)
      let existingTagIds = try await MovieTag.query(on: fluent.db())
        .filter(\.$movie.$id == movie.requireID())
        .with(\.$tag)
        .all()
        .map { try $0.tag.requireID() }

      for tag in tags {
        let tagId = try tag.requireID()
        if !existingTagIds.contains(tagId) {
          let movieTag = MovieTag(
            movieId: try movie.requireID(),
            tagId: tagId,
            addedByAutoTag: false
          )
          try await movieTag.save(on: fluent.db())
        }
      }
    }

    // Update usage counts
    try await updateTagUsageCounts(for: validSlugs)

    // Return updated movie
    let updatedMovie = try await Movie.query(on: fluent.db())
      .filter(\.$id == movie.requireID())
      .with(\.$tags)
      .first()!

    return MovieResponse(movie: updatedMovie, tags: updatedMovie.tags)
  }

  func getAllTags(sortBy: String = "usage", order: String = "desc") async throws -> TagsListResponse
  {
    let query = Tag.query(on: fluent.db())

    switch sortBy {
    case "usage":
      if order == "desc" {
        query.sort(\.$usageCount, DatabaseQuery.Sort.Direction.descending)
      } else {
        query.sort(\.$usageCount, DatabaseQuery.Sort.Direction.ascending)
      }
    case "name", "title":
      if order == "desc" {
        query.sort(\.$title, DatabaseQuery.Sort.Direction.descending)
      } else {
        query.sort(\.$title, DatabaseQuery.Sort.Direction.ascending)
      }
    case "created":
      if order == "desc" {
        query.sort(\.$createdAt, DatabaseQuery.Sort.Direction.descending)
      } else {
        query.sort(\.$createdAt, DatabaseQuery.Sort.Direction.ascending)
      }
    default:
      query.sort(\.$usageCount, DatabaseQuery.Sort.Direction.descending)
    }

    let tags = try await query.all()
    let responses = tags.map(TagResponse.init)

    return TagsListResponse(tags: responses, totalCount: tags.count)
  }

  func getTag(slug: String) async throws -> TagResponse {
    let tag = try await Tag.query(on: fluent.db())
      .filter(\.$slug == slug)
      .first()
      .unwrap(orError: MovieServiceError.tagNotFound(slug))

    return TagResponse(tag: tag)
  }

  // MARK: - Auto-Tagging

  func generateAutoTags(
    movieId: String,
    provider: String?,
    suggestionsOnly: Bool,
    customPrompt: String?
  ) async throws -> AutoTagResponse {
    let movie = try await getMovieEntity(id: movieId)

    // Anthropic-only selection
    let chosen = provider?.lowercased()
    let llmProvider: LLMProvider
    if chosen == nil || chosen == "auto" {
      guard let key = config.anthropicApiKey, !key.isEmpty else {
        throw MovieServiceError.missingApiKey("Anthropic")
      }
      llmProvider = .anthropic(apiKey: key)
    } else {
      switch chosen! {
      case "anthropic":
        guard let apiKey = config.anthropicApiKey, !apiKey.isEmpty else {
          throw MovieServiceError.missingApiKey("Anthropic")
        }
        llmProvider = .anthropic(apiKey: apiKey)
      default:
        throw MovieServiceError.unsupportedProvider(chosen!)
      }
    }

    // Generate suggestions
    let external = await llmService.fetchExternalSummary(for: movie)
    var response = try await llmService.generateTags(
      for: movie,
      using: llmProvider,
      availableTags: config.moodBuckets,
      customPrompt: customPrompt ?? config.autoTaggingPrompt,
      maxTags: config.maxAutoTags,
      externalInfo: external
    )

    // If confidence is low or suggestions look generic, ask the model to refine once
    let looksGeneric =
      Set(response.suggestions).contains("dialogue-driven")
      || Set(response.suggestions).contains("modern-masterpieces")
    if response.confidence < 0.72 || looksGeneric {
      do {
        response = try await llmService.refineTags(
          for: movie,
          using: llmProvider,
          availableTags: config.moodBuckets,
          initial: response,
          externalInfo: external,
          maxTags: config.maxAutoTags
        )
      } catch {
        // Fall back silently if refinement fails
      }
    }

    // Validate suggested tags
    var validSuggestions = response.suggestions.filter { config.moodBuckets[$0] != nil }

    // Heuristic post-filtering using external summary and metadata
    validSuggestions = postFilterSuggestions(validSuggestions, summary: external, movie: movie)
    let finalResponse = AutoTagResponse(
      suggestions: validSuggestions,
      confidence: response.confidence,
      reasoning: response.reasoning
    )

    // Apply tags if not suggestions-only
    if !suggestionsOnly && !validSuggestions.isEmpty {
      _ = try await updateMovieTags(
        movieId: movieId,
        tagSlugs: validSuggestions,
        replaceAll: false
      )
    }

    return finalResponse
  }

  // MARK: - Post-filtering heuristics
  private func postFilterSuggestions(_ suggestions: [String], summary: String?, movie: Movie)
    -> [String]
  {
    guard let text = summary?.lowercased() ?? movie.overview?.lowercased() else {
      return suggestions
    }
    var result: [String] = []
    let words =
      text
      .replacingOccurrences(of: "\n", with: " ")
      .replacingOccurrences(of: "\t", with: " ")

    for tag in suggestions {
      switch tag {
      case "time-twists":
        // Require explicit temporal mechanics
        let ok = [
          "time travel", "time-travel", "time loop", "timeloop", "looping time", "resetting day",
          "timeline",
          "timelines", "temporal", "time machine", "alternate timeline", "paradox",
        ].contains(where: { words.contains($0) })
        if ok { result.append(tag) }
      case "modern-masterpieces":
        // Only when there is explicit critical consensus language
        let ok = [
          "masterpiece", "critically acclaimed", "universal acclaim", "academy award", "oscar",
          "palme d'or", "landmark film", "canon", "best of all time",
        ].contains(where: { words.contains($0) })
        if ok { result.append(tag) }
      case "psychological-pressure-cooker":
        // Prefer one-room-pressure-cooker when confined setting dominates
        let hasOneRoom = [
          "single room", "one room", "jury room", "confined space", "bottle episode", "bottle film",
        ].contains(where: { words.contains($0) })
        let hasPsych = [
          "paranoia", "psychological", "mental breakdown", "gaslight", "psychosis",
          "claustrophobic",
        ].contains(where: { words.contains($0) })
        if hasPsych || !hasOneRoom { result.append(tag) }
      default:
        result.append(tag)
      }
    }
    // Deduplicate and cap at 4 (server config enforces elsewhere, but keep tidy)
    let unique = Array(NSOrderedSet(array: result)) as? [String] ?? result
    return Array(unique.prefix(4))
  }

  // MARK: - Search

  func searchMovies(query: String, limit: Int = 20, includeTags: Bool = false) async throws
    -> MoviesListResponse
  {
    let searchQuery = Movie.query(on: fluent.db())
    // Search only in title
    searchQuery.group(.or) { group in
      group.filter(\.$title ~~ query)
    }

    if includeTags {
      searchQuery.with(\.$tags)
    }

    let movies =
      try await searchQuery
      .sort(\.$title)
      .limit(limit)
      .all()

    let responses = movies.map { movie in
      MovieResponse(movie: movie, tags: includeTags ? movie.tags : [])
    }

    return MoviesListResponse(
      movies: responses,
      totalCount: movies.count,
      offset: 0,
      limit: limit
    )
  }

  func searchTags(query: String) async throws -> TagsListResponse {
    // Search in mood buckets
    let matchingBuckets = config.moodBuckets.filter { slug, bucket in
      slug.contains(query.lowercased()) || bucket.title.lowercased().contains(query.lowercased())
        || bucket.description.lowercased().contains(query.lowercased())
    }

    // Convert to tag responses
    let responses = matchingBuckets.map { slug, bucket in
      TagResponse(tag: Tag(slug: slug, title: bucket.title, description: bucket.description))
    }

    return TagsListResponse(tags: responses, totalCount: responses.count)
  }

  // MARK: - Playback

  
  func getAvailableSubtitles(movieId: String) async throws -> [SubtitleTrack] {
    let movie = try await getMovieEntity(id: movieId)

    // Return embedded subtitles from Jellyfin
    return movie.jellyfinMetadata?.mediaStreams
      .filter { $0.type.lowercased() == "subtitle" }
      .map { stream in
        SubtitleTrack(
          index: stream.index,
          title: stream.title,
          language: stream.language,
          codec: stream.codec ?? "unknown",
          isForced: stream.isForced ?? false,
          isDefault: stream.isDefault ?? false,
          url: nil
        )
      } ?? []
  }

  // MARK: - Clients API helpers
  func getClientMovies() async throws -> ClientMoviesListResponse {
    // Fetch all movies with tags
    let movies = try await Movie.query(on: fluent.db())
      .with(\.$tags)
      .sort(\.$title)
      .all()
    let total = movies.count
    let ids = movies.map { $0.jellyfinId }
    let live = try await jellyfinService.fetchItems(ids: ids)
    let liveById = Dictionary(uniqueKeysWithValues: live.map { ($0.id, $0) })
    let items = movies.map { m in buildClientMovie(from: m, liveMeta: liveById[m.jellyfinId]) }
    return ClientMoviesListResponse(movies: items, totalCount: total)
  }

  /// Return up to 24 movies similar to the given movie id (UUID or Jellyfin id)
  /// Primary source: Jellyfin Similar API; Fallback: overlap by mood tags in local DB
  func getSimilarClientMovies(id: String, maxCount: Int = 12) async throws -> [ClientMovieResponse] {
    // Resolve seed movie
    let seed = try await getMovieEntity(id: id)

    // Try Jellyfin Similar first
    do {
      let similar = try await jellyfinService.getSimilarMovies(to: seed.jellyfinId, limit: maxCount)
      if !similar.isEmpty {
        let ids = similar.map { $0.id }
        let local = try await Movie.query(on: fluent.db())
          .filter(\.$jellyfinId ~~ ids)
          .with(\.$tags)
          .all()
        if !local.isEmpty {
          // Preserve order from Jellyfin
          let byId = Dictionary(uniqueKeysWithValues: local.map { ($0.jellyfinId, $0) })
          var out: [ClientMovieResponse] = []
          out.reserveCapacity(min(maxCount, local.count))
          for meta in similar {
            if let m = byId[meta.id], m.jellyfinId != seed.jellyfinId {
              out.append(buildClientMovie(from: m, liveMeta: meta))
              if out.count >= maxCount { break }
            }
          }
          if !out.isEmpty { return out }
        }
      }
    } catch {
      // Ignore and fallback
    }

    // Fallback: overlap by mood tags (descending), tie-break by year closeness and genre/director overlap
    let seedTags = try await MovieTag.query(on: fluent.db())
      .filter(\.$movie.$id == seed.requireID())
      .with(\.$tag)
      .all()
      .map { $0.tag }
    let seedTagSlugs = Set(seedTags.map { $0.slug })

    let candidates = try await Movie.query(on: fluent.db())
      .filter(\.$id != seed.requireID())
      .with(\.$tags)
      .all()

    struct ScoredMovie { let movie: Movie; let score: Int; let yearDelta: Int; let bonus: Int }
    let seedYear = seed.year
    let seedGenres = Set(seed.jellyfinMetadata?.genres ?? [])
    let seedDirector = seed.jellyfinMetadata?.director?.lowercased()

    var scored: [ScoredMovie] = []
    scored.reserveCapacity(candidates.count)
    for m in candidates {
      let slugs = Set(m.tags.map { $0.slug })
      let overlap = slugs.intersection(seedTagSlugs).count
      if overlap == 0 { continue }
      let yearDelta = {
        guard let a = seedYear, let b = m.year else { return Int.max }
        return abs(a - b)
      }()
      let genres = Set(m.jellyfinMetadata?.genres ?? [])
      let genreOverlap = genres.intersection(seedGenres).count
      let directorBonus: Int = {
        guard let d1 = seedDirector, let d2 = m.jellyfinMetadata?.director?.lowercased() else { return 0 }
        return d1 == d2 ? 1 : 0
      }()
      let bonus = min(2, genreOverlap) + directorBonus
      scored.append(ScoredMovie(movie: m, score: overlap, yearDelta: yearDelta, bonus: bonus))
    }

    let ordered = scored.sorted { a, b in
      if a.score != b.score { return a.score > b.score }
      if a.bonus != b.bonus { return a.bonus > b.bonus }
      if a.yearDelta != b.yearDelta { return a.yearDelta < b.yearDelta }
      return a.movie.title < b.movie.title
    }
    let picked = ordered.prefix(maxCount).map { $0.movie }
    if picked.isEmpty { return [] }
    let live = try await jellyfinService.fetchItems(ids: picked.map { $0.jellyfinId })
    let liveById = Dictionary(uniqueKeysWithValues: live.map { ($0.id, $0) })
    return picked.map { buildClientMovie(from: $0, liveMeta: liveById[$0.jellyfinId]) }
  }

  // MARK: - Clients Home helpers
  /// 5 unwatched movies selected deterministically using a salt (falls back to all if none unwatched)
  func getBannerMovies(maxCount: Int = 5, salt: String? = nil) async throws -> [ClientMovieResponse] {
    let movies = try await Movie.query(on: fluent.db()).with(\.$tags).all()
    guard !movies.isEmpty else { return [] }
    

    // Get live data for ALL movies with backdrops to check watch status
    let ids = movies.map { $0.jellyfinId }
    let live = try await jellyfinService.fetchItems(ids: ids)
    let liveById = Dictionary(uniqueKeysWithValues: live.map { ($0.id, $0) })
    // Prefer unwatched; fallback to all movies
    let unwatched = movies.filter { m in !(liveById[m.jellyfinId]?.userData?.played ?? false) }
    let pool = unwatched.isEmpty ? movies : unwatched

    // Deterministic ordering based on salt
    let saltValue = salt ?? Date().iso8601String
    func hash64(_ s: String) -> UInt64 {
      // FNV-1a 64-bit
      let fnvOffset: UInt64 = 14695981039346656037
      let fnvPrime: UInt64 = 1099511628211
      var hash = fnvOffset
      for byte in s.utf8 { hash ^= UInt64(byte); hash = hash &* fnvPrime }
      return hash
    }
    let ordered = pool.sorted { a, b in
      let ha = hash64(saltValue + a.jellyfinId)
      let hb = hash64(saltValue + b.jellyfinId)
      if ha == hb { return a.jellyfinId < b.jellyfinId }
      return ha < hb
    }
    let picked = Array(ordered.prefix(maxCount))
    return picked.map { buildClientMovie(from: $0, liveMeta: liveById[$0.jellyfinId]) }
  }

  /// Movies with progress for continue watching (movies only), sorted by last played desc
  func getContinueWatchingMovies(maxCount: Int = 10) async throws -> [ClientMovieResponse] {
    // Pull resume items from Jellyfin and map to local movies
    let resumeItems = try await jellyfinService.getResumeItems(limit: maxCount)
    if resumeItems.isEmpty { return [] }
    let ids = resumeItems.map { $0.id }
    // Load matching local entities
    let local = try await Movie.query(on: fluent.db())
      .filter(\.$jellyfinId ~~ ids)
      .with(\.$tags)
      .all()
    let byId = Dictionary(uniqueKeysWithValues: local.map { ($0.jellyfinId, $0) })
    // Keep original resume order
    var out: [ClientMovieResponse] = []
    out.reserveCapacity(resumeItems.count)
    for meta in resumeItems {
      if let m = byId[meta.id] {
        out.append(buildClientMovie(from: m, liveMeta: meta))
      }
    }
    return out
  }

  /// 10 newest movies by Jellyfin DateCreated desc (server truth)
  func getRecentlyAddedMovies(maxCount: Int = 10) async throws -> [ClientMovieResponse] {
    let recent = try await jellyfinService.getRecentlyAddedMovies(limit: maxCount)
    if recent.isEmpty { return [] }
    // Map to local models preserving order
    let ids = recent.map { $0.id }
    let local = try await Movie.query(on: fluent.db())
      .filter(\.$jellyfinId ~~ ids)
      .with(\.$tags)
      .all()
    let byId = Dictionary(uniqueKeysWithValues: local.map { ($0.jellyfinId, $0) })
    var out: [ClientMovieResponse] = []
    out.reserveCapacity(recent.count)
    for meta in recent {
      if let m = byId[meta.id] {
        out.append(buildClientMovie(from: m, liveMeta: meta))
      }
    }
    return out
  }

  /// Get total progress statistics
  func getTotalProgress() async throws -> (totalMovies: Int, watchedMovies: Int, progressPercent: Float) {
    // Get all movies
    let movies = try await Movie.query(on: fluent.db()).all()
    let totalMovies = movies.count
    
    if totalMovies == 0 {
      return (totalMovies: 0, watchedMovies: 0, progressPercent: 0.0)
    }
    
    // Get live data for all movies to check watch status
    let ids = movies.map { $0.jellyfinId }
    let live = try await jellyfinService.fetchItems(ids: ids)
    let liveById = Dictionary(uniqueKeysWithValues: live.map { ($0.id, $0) })
    
    // Count watched movies
    let watchedMovies = movies.filter { m in
      let played = liveById[m.jellyfinId]?.userData?.played ?? false
      return played
    }.count
    
    let progressPercent = Float(watchedMovies) / Float(totalMovies) * 100.0
    
    return (totalMovies: totalMovies, watchedMovies: watchedMovies, progressPercent: progressPercent)
  }

  /// Random mood pick (excluding provided slugs) with all movies for that mood
  func getRandomMoodSection(excluding excluded: [String]) async throws -> (mood: String, moodTitle: String, items: [ClientMovieResponse])? {
    // Build candidate moods
    let allMoods = Array(config.moodBuckets.keys)
    let excludeSet = Set(excluded.compactMap { $0.isEmpty ? nil : $0 })
    var pool = allMoods.filter { !excludeSet.contains($0) }
    if pool.isEmpty { pool = allMoods }
    guard let mood = pool.randomElement() else { return nil }
    let moodTitle = config.moodBuckets[mood]?.title ?? mood
    // Fetch movies tagged with this mood
    guard let tag = try await Tag.query(on: fluent.db()).filter(\.$slug == mood).first() else {
      return nil
    }
    let movies = try await Movie.query(on: fluent.db())
      .join(MovieTag.self, on: \Movie.$id == \MovieTag.$movie.$id)
      .filter(MovieTag.self, \.$tag.$id == tag.requireID())
      .with(\.$tags)
      .all()
    if movies.isEmpty { return (mood, moodTitle, []) }
    let ids = movies.map { $0.jellyfinId }
    let live = try await jellyfinService.fetchItems(ids: ids)
    let liveById = Dictionary(uniqueKeysWithValues: live.map { ($0.id, $0) })
    let items = movies.map { buildClientMovie(from: $0, liveMeta: liveById[$0.jellyfinId]) }
    // max items at 10
    return (mood, moodTitle, Array(items.prefix(10)))
  }

  func getClientMovies(withTag tagSlug: String) async throws -> ClientMoviesListResponse {
    guard config.moodBuckets[tagSlug] != nil else {
      throw MovieServiceError.tagNotFound(tagSlug)
    }
    let tag = try await Tag.query(on: fluent.db())
      .filter(\.$slug == tagSlug)
      .first()
      .unwrap(orError: MovieServiceError.tagNotFound(tagSlug))
    let movies = try await Movie.query(on: fluent.db())
      .join(MovieTag.self, on: \Movie.$id == \MovieTag.$movie.$id)
      .filter(MovieTag.self, \.$tag.$id == tag.requireID())
      .with(\.$tags)
      .sort(\.$title)
      .all()
    let ids = movies.map { $0.jellyfinId }
    let live = try await jellyfinService.fetchItems(ids: ids)
    let liveById = Dictionary(uniqueKeysWithValues: live.map { ($0.id, $0) })
    let items = movies.map { m in buildClientMovie(from: m, liveMeta: liveById[m.jellyfinId]) }
    return ClientMoviesListResponse(movies: items, totalCount: items.count)
  }

  func getClientTimeline() async throws -> [ClientTimelineItem] {
    // Fetch all with tags
    let movies = try await Movie.query(on: fluent.db())
      .with(\.$tags)
      .all()
    // Live overlay for all movies in the response
    let ids = movies.map { $0.jellyfinId }
    let live = try await jellyfinService.fetchItems(ids: ids)
    let liveById = Dictionary(uniqueKeysWithValues: live.map { ($0.id, $0) })
    // Group by year (unknown grouped under nil)
    var groups: [Int?: [Movie]] = [:]
    for m in movies {
      groups[m.year, default: []].append(m)
    }
    // Sort groups by year asc with unknown last
    let orderedYears: [Int?] = groups.keys.sorted { a, b in
      switch (a, b) {
      case (let ya?, let yb?): return ya < yb
      case (nil, _?): return false
      case (_?, nil): return true
      default: return false
      }
    }
    // Build response with per-year movies sorted by title
    var timeline: [ClientTimelineItem] = []
    for key in orderedYears {
      let bucket = (groups[key] ?? []).sorted { $0.title < $1.title }
      let moviesOut = bucket.map { buildClientMovie(from: $0, liveMeta: liveById[$0.jellyfinId]) }
      let yearOut: ClientTimelineYear = key == nil ? .unknown : .known(key!)
      timeline.append(ClientTimelineItem(year: yearOut, movies: moviesOut))
    }
    // Ensure unknown group exists at end even if empty? Not required; only include present groups
    return timeline
  }

  private func buildClientMovie(from movie: Movie, liveMeta: JellyfinMovieMetadata? = nil) -> ClientMovieResponse {
    let imdbId =
      movie.jellyfinMetadata?.providerIds?["Imdb"] ?? movie.jellyfinMetadata?.providerIds?["IMDb"]
    
    // All image URLs stored in database with existence validation during sync
    let images = ClientImages(
      poster: movie.posterUrl,
      backdrop: movie.backdropUrl,
      titleLogo: movie.logoUrl
    )
    let effectiveMeta = liveMeta ?? movie.jellyfinMetadata
    let ticks = effectiveMeta?.userData?.playbackPositionTicks ?? 0
    let progressMs: Int? = ticks > 0 ? Int(ticks / 10_000) : nil
    let totalMs: Int? = (effectiveMeta?.runTimeTicks).map { Int($0 / 10_000) }
    let progressPercent: Float? = {
      guard let p = progressMs, let t = totalMs, t > 0 else { return nil }
      return min(100, max(0, (Float(p) / Float(t)) * 100))
    }()

    return ClientMovieResponse(
      id: movie.id,
      jellyfinId: movie.jellyfinId,
      title: movie.title,
      year: movie.year,
      runtime: runtimeString(from: movie.runtimeMinutes),
      runtimeMinutes: movie.runtimeMinutes,
      description: movie.overview,
      images: images,
      tags: movie.tags.map(MinimalTagResponse.init),
      imdbId: imdbId,
      isWatched: effectiveMeta?.userData?.played ?? false,
      progressMs: progressMs,
      progressPercent: progressPercent
    )
  }

  func runtimeString(from minutes: Int?) -> String? {
    guard let minutes = minutes, minutes >= 0 else { return nil }
    let h = minutes / 60
    let m = minutes % 60
    switch (h, m) {
    case (0, _): return "\(m)min"
    case (_, 0): return "\(h)h"
    default: return "\(h)h \(m)min"
    }
  }

  // MARK: - Maintenance
  func resetAllTags() async throws {
    // Delete all pivot rows
    try await MovieTag.query(on: fluent.db()).delete()
    // Reset tag usage counts
    let allTags = try await Tag.query(on: fluent.db()).all()
    for tag in allTags {
      tag.usageCount = 0
      try await tag.save(on: fluent.db())
    }
  }

  /// Delete all movies and their tag relations; reset tag usage counts.
  func clearAllMovies() async throws {
    // Delete all pivots first to avoid orphans
    try await MovieTag.query(on: fluent.db()).delete()
    // Delete all movies
    try await Movie.query(on: fluent.db()).delete()
    // Reset tag usage counts
    let allTags = try await Tag.query(on: fluent.db()).all()
    for tag in allTags {
      tag.usageCount = 0
      try await tag.save(on: fluent.db())
    }
    logger.info("Cleared all movies and reset tag usage counts")
  }

  // MARK: - Export/Import
  func exportTagsMap() async throws -> [String: ExportMovieTags] {
    let movies = try await Movie.query(on: fluent.db())
      .with(\.$tags)
      .all()
    var map: [String: ExportMovieTags] = [:]
    for m in movies {
      // Always export using Jellyfin ID as the key so imports are stable across DB resets
      let idString = m.jellyfinId
      map[idString] = ExportMovieTags(title: m.title, tags: m.tags.map { $0.slug })
    }
    return map
  }

  func importTagsMap(_ map: [String: ExportMovieTags], replaceAll: Bool = true) async throws {
    for (movieKey, payload) in map {
      do {
        // First try by provided key (Jellyfin ID preferred; UUID supported)
        do {
          _ = try await updateMovieTags(
            movieId: movieKey, tagSlugs: payload.tags, replaceAll: replaceAll)
          continue
        } catch {
          // Fall through to title-based matching
        }

        // Fallback: match by exact title/originalTitle
        let title = payload.title
        let titleQuery = Movie.query(on: fluent.db())
        titleQuery.group(.or) { qb in
          qb.filter(\.$title == title)
          qb.filter(\.$originalTitle == title)
        }
        if let byTitle = try await titleQuery.first() {
          let idString = (try? byTitle.requireID().uuidString) ?? byTitle.jellyfinId
          _ = try await updateMovieTags(
            movieId: idString, tagSlugs: payload.tags, replaceAll: replaceAll)
        } else {
          logger.error("Import: No movie found for key=\(movieKey) or title=\(title)")
        }
      } catch {
        logger.error(
          "Failed to import tags for movie key=\(movieKey) title=\(payload.title): \(error)")
      }
    }
    let uniqueSlugs = Array(Set(map.values.flatMap { $0.tags }))
    try await updateTagUsageCounts(for: uniqueSlugs)
  }

  // MARK: - Jellyfin Sync

  func syncWithJellyfin(fullSync: Bool = false) async throws -> SyncStatusResponse {
    guard !isSyncing else {
      throw MovieServiceError.syncAlreadyRunning
    }

    isSyncing = true
    let startTime = Date()
    var stats = SyncStats()

    defer {
      isSyncing = false
      lastSyncAt = startTime
      lastSyncDuration = Date().timeIntervalSince(startTime)
      lastSyncStats = stats
    }

    logger.info("Starting Jellyfin sync (full: \(fullSync))")

    do {
      var jellyfinMovies: [JellyfinMovieMetadata]
      do {
        jellyfinMovies = try await jellyfinService.fetchAllMovies()
      } catch let e as JellyfinError {
        // Attempt auto-login and retry once on 401
        switch e {
        case .httpError(let code, _):
          if code == 401 {
            let refreshed = try await attemptAutoLoginAndUpdate()
            if refreshed {
              jellyfinMovies = try await jellyfinService.fetchAllMovies()
            } else {
              throw e
            }
          } else {
            throw e
          }
        default:
          throw e
        }
      }
      stats.moviesFound = jellyfinMovies.count
      // Publish initial totals so clients can compute progress
      self.lastSyncStats = stats

      for jellyfinMovie in jellyfinMovies {
        do {
          let existingMovie = try await Movie.query(on: fluent.db())
            .filter(\.$jellyfinId == jellyfinMovie.id)
            .first()

          if let existing = existingMovie {
            // Update existing movie
            existing.title = jellyfinMovie.name
            existing.originalTitle = jellyfinMovie.originalTitle
            existing.year = jellyfinMovie.productionYear
            existing.overview = jellyfinMovie.overview
            existing.runtimeMinutes = jellyfinMovie.runtimeMinutes
            existing.genres = jellyfinMovie.genres
            existing.director = jellyfinMovie.director
            existing.cast = jellyfinMovie.cast
            // Store all image URLs with existence validation
            if let baseItem = try? await jellyfinService.fetchMovie(id: jellyfinMovie.id) {
              logger.info("Fetching images for existing movie: \(jellyfinMovie.name)")
              existing.posterUrl = jellyfinService.getImageUrl(for: baseItem, imageType: .primary, quality: 85)
              existing.backdropUrl = jellyfinService.getImageUrl(for: baseItem, imageType: .backdrop, quality: 85)
              existing.logoUrl = jellyfinService.getImageUrl(for: baseItem, imageType: .logo, quality: 85)
              logger.info("Image URLs - Poster: \(existing.posterUrl ?? "nil"), Backdrop: \(existing.backdropUrl ?? "nil"), Logo: \(existing.logoUrl ?? "nil")")
            }
            
            existing.jellyfinMetadata = jellyfinMovie

            try await existing.save(on: fluent.db())
            stats.moviesUpdated += 1
            // Publish progress after each update
            self.lastSyncStats = stats
          } else {
            // Create new movie
            let movie = jellyfinMovie.toMovie()
            // Store all image URLs with existence validation
            if let baseItem = try? await jellyfinService.fetchMovie(id: jellyfinMovie.id) {
              logger.info("Fetching images for new movie: \(jellyfinMovie.name)")
              movie.posterUrl = jellyfinService.getImageUrl(for: baseItem, imageType: .primary, quality: 85)
              movie.backdropUrl = jellyfinService.getImageUrl(for: baseItem, imageType: .backdrop, quality: 85)
              movie.logoUrl = jellyfinService.getImageUrl(for: baseItem, imageType: .logo, quality: 85)
              logger.info("Image URLs - Poster: \(movie.posterUrl ?? "nil"), Backdrop: \(movie.backdropUrl ?? "nil"), Logo: \(movie.logoUrl ?? "nil")")
            }

            try await movie.save(on: fluent.db())
            stats.moviesUpdated += 1
            // Publish progress after each creation
            self.lastSyncStats = stats
          }
        } catch {
          stats.errors.append("Failed to sync movie \(jellyfinMovie.name): \(error)")
          logger.error("Failed to sync movie \(jellyfinMovie.name): \(error)")
          // Publish errors as they happen
          self.lastSyncStats = stats
        }
      }
      // Delete movies that no longer exist in Jellyfin
      do {
        let jellyfinIds = Set(jellyfinMovies.map { $0.id })
        let allDbMovies = try await Movie.query(on: fluent.db()).all()
        let orphaned = allDbMovies.filter { !jellyfinIds.contains($0.jellyfinId) }
        if !orphaned.isEmpty {
          logger.info("Deleting \(orphaned.count) movies no longer present in Jellyfin")
        }
        for movie in orphaned {
          do {
            let title = movie.title
            try await movie.delete(on: fluent.db())
            stats.moviesDeleted += 1
            // Publish progress as deletions complete
            self.lastSyncStats = stats
            logger.info("Deleted movie '\(title)' (jellyfinId=\(movie.jellyfinId)) from local DB")
          } catch {
            stats.errors.append("Failed to delete movie \(movie.jellyfinId): \(error)")
            logger.error("Failed to delete orphaned movie \(movie.jellyfinId): \(error)")
            self.lastSyncStats = stats
          }
        }
        // Recalculate tag usage counts since pivots may have been removed via cascade
        let allTags = try await Tag.query(on: fluent.db()).all()
        let allSlugs = allTags.map { $0.slug }
        try await updateTagUsageCounts(for: allSlugs)
      } catch {
        stats.errors.append("Cleanup step failed: \(error)")
        logger.error("Cleanup of orphaned movies failed: \(error)")
      }

      logger.info(
        "Jellyfin sync completed: \(stats.moviesFound) found, \(stats.moviesUpdated) updated, \(stats.moviesDeleted) deleted"
      )

    } catch {
      stats.errors.append("Sync failed: \(error)")
      logger.error("Jellyfin sync failed: \(error)")
      throw error
    }

    return SyncStatusResponse(
      isRunning: false,
      lastSyncAt: startTime,
      lastSyncDuration: Date().timeIntervalSince(startTime),
      moviesFound: stats.moviesFound,
      moviesUpdated: stats.moviesUpdated,
      moviesDeleted: stats.moviesDeleted,
      errors: stats.errors
    )
  }

  func getSyncStatus() async throws -> SyncStatusResponse {
    return SyncStatusResponse(
      isRunning: isSyncing,
      lastSyncAt: lastSyncAt,
      lastSyncDuration: lastSyncDuration,
      moviesFound: lastSyncStats.moviesFound,
      moviesUpdated: lastSyncStats.moviesUpdated,
      moviesDeleted: lastSyncStats.moviesDeleted,
      errors: lastSyncStats.errors
    )
  }

  func testJellyfinConnection() async throws -> ConnectionTestResponse {
    do {
      let isConnected = try await jellyfinService.testConnection()
      if isConnected {
        let serverInfo = try await jellyfinService.getServerInfo()
        return ConnectionTestResponse(success: true, serverInfo: serverInfo, error: nil)
      } else {
        return ConnectionTestResponse(
          success: false, serverInfo: nil, error: "Authentication failed")
      }
    } catch {
      return ConnectionTestResponse(
        success: false, serverInfo: nil, error: error.localizedDescription)
    }
  }

  // MARK: - Private Helpers

  private func validateImageUrl(_ url: String) async -> Bool {
    guard !url.isEmpty else { return false }
    
    do {
      var request = HTTPClientRequest(url: url)
      request.method = .HEAD
      let response = try await jellyfinService.httpClient.execute(request, timeout: .seconds(5))
      return response.status == .ok
    } catch {
      logger.debug("Image validation failed for \(url): \(error)")
      return false
    }
  }

  private func getMovieEntity(id: String) async throws -> Movie {
    if let uuid = UUID(uuidString: id) {
      return try await Movie.query(on: fluent.db())
        .filter(\.$id == uuid)
        .first()
        .unwrap(orError: MovieServiceError.movieNotFound(id))
    } else {
      return try await Movie.query(on: fluent.db())
        .filter(\.$jellyfinId == id)
        .first()
        .unwrap(orError: MovieServiceError.movieNotFound(id))
    }
  }

  private func validateTagSlugs(_ slugs: [String]) throws -> [String] {
    var validSlugs: [String] = []

    for slug in slugs {
      guard config.moodBuckets[slug] != nil else {
        throw MovieServiceError.tagNotFound(slug)
      }
      validSlugs.append(slug)
    }

    return validSlugs
  }

  private func getOrCreateTag(slug: String) async throws -> Tag {
    if let existing = try await Tag.query(on: fluent.db()).filter(\.$slug == slug).first() {
      return existing
    }

    guard let bucket = config.moodBuckets[slug] else {
      throw MovieServiceError.tagNotFound(slug)
    }

    let tag = Tag(slug: slug, title: bucket.title, description: bucket.description)
    try await tag.save(on: fluent.db())
    return tag
  }

  private func updateTagUsageCounts(for slugs: [String]) async throws {
    for slug in slugs {
      if let tag = try await Tag.query(on: fluent.db()).filter(\.$slug == slug).first() {
        let count = try await MovieTag.query(on: fluent.db())
          .filter(\.$tag.$id == tag.requireID())
          .count()
        tag.usageCount = count
        try await tag.save(on: fluent.db())
      }
    }
  }
}

// MARK: - Supporting Types

private struct SyncStats {
  var moviesFound: Int = 0
  var moviesUpdated: Int = 0
  var moviesDeleted: Int = 0
  var errors: [String] = []
}

enum MovieServiceError: Error, CustomStringConvertible {
  case movieNotFound(String)
  case tagNotFound(String)
  case syncAlreadyRunning
  case missingApiKey(String)
  case unsupportedProvider(String)

  var description: String {
    switch self {
    case .movieNotFound(let id):
      return "Movie not found: \(id)"
    case .tagNotFound(let slug):
      return "Tag not found: \(slug)"
    case .syncAlreadyRunning:
      return "Sync is already running"
    case .missingApiKey(let provider):
      return "Missing API key for \(provider)"
    case .unsupportedProvider(let provider):
      return "Unsupported LLM provider: \(provider)"
    }
  }
}
