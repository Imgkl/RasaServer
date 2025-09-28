import Foundation
import FluentKit
import FluentSQLiteDriver
import Hummingbird

// MARK: - Movie Model
final class Movie: Model, @unchecked Sendable {
    static let schema = "movies"
    
    @ID(key: .id)
    var id: UUID?
    
    @Field(key: "jellyfin_id")
    var jellyfinId: String
    
    @Field(key: "title")
    var title: String
    
    @Field(key: "original_title")
    var originalTitle: String?
    
    @Field(key: "year")
    var year: Int?
    
    @Field(key: "overview")
    var overview: String?
    
    @Field(key: "runtime_minutes")
    var runtimeMinutes: Int?
    
    @Field(key: "genres")
    var genres: [String]
    
    @Field(key: "director")
    var director: String?
    
    @Field(key: "cast")
    var cast: [String]
    
    @Field(key: "poster_url")
    var posterUrl: String?
    
    @Field(key: "backdrop_url")
    var backdropUrl: String?
    
    @Field(key: "logo_url")
    var logoUrl: String?
    
    @Field(key: "trailer_deeplink")
    var trailerDeepLink: String?
    
    @Field(key: "jellyfin_metadata")
    var jellyfinMetadata: JellyfinMovieMetadata?
    
    @Siblings(through: MovieTag.self, from: \.$movie, to: \.$tag)
    var tags: [Tag]
    
    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?
    
    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?
    
    init() {}
    
    init(
        id: UUID? = nil,
        jellyfinId: String,
        title: String,
        originalTitle: String? = nil,
        year: Int? = nil,
        overview: String? = nil,
        runtimeMinutes: Int? = nil,
        genres: [String] = [],
        director: String? = nil,
        cast: [String] = [],
        posterUrl: String? = nil,
        backdropUrl: String? = nil,
        logoUrl: String? = nil,
        trailerDeepLink: String? = nil,
        jellyfinMetadata: JellyfinMovieMetadata? = nil
    ) {
        self.id = id
        self.jellyfinId = jellyfinId
        self.title = title
        self.originalTitle = originalTitle
        self.year = year
        self.overview = overview
        self.runtimeMinutes = runtimeMinutes
        self.genres = genres
        self.director = director
        self.cast = cast
        self.posterUrl = posterUrl
        self.backdropUrl = backdropUrl
        self.logoUrl = logoUrl
        self.trailerDeepLink = trailerDeepLink
        self.jellyfinMetadata = jellyfinMetadata
    }
}

// MARK: - Tag Model
final class Tag: Model, @unchecked Sendable {
    static let schema = "tags"
    
    @ID(key: .id)
    var id: UUID?
    
    @Field(key: "slug")
    var slug: String
    
    @Field(key: "title")
    var title: String
    
    @Field(key: "description")
    var description: String
    
    @Field(key: "usage_count")
    var usageCount: Int
    
    @Siblings(through: MovieTag.self, from: \.$tag, to: \.$movie)
    var movies: [Movie]
    
    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?
    
    init() {}
    
    init(
        id: UUID? = nil,
        slug: String,
        title: String,
        description: String,
        usageCount: Int = 0
    ) {
        self.id = id
        self.slug = slug
        self.title = title
        self.description = description
        self.usageCount = usageCount
    }
}

// MARK: - Movie-Tag Pivot
final class MovieTag: Model, @unchecked Sendable {
    static let schema = "movie_tags"
    
    @ID(key: .id)
    var id: UUID?
    
    @Parent(key: "movie_id")
    var movie: Movie
    
    @Parent(key: "tag_id")
    var tag: Tag
    
    @Field(key: "added_by_auto_tag")
    var addedByAutoTag: Bool
    
    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?
    
    init() {}
    
    init(
        id: UUID? = nil,
        movieId: Movie.IDValue,
        tagId: Tag.IDValue,
        addedByAutoTag: Bool = false
    ) {
        self.id = id
        self.$movie.id = movieId
        self.$tag.id = tagId
        self.addedByAutoTag = addedByAutoTag
    }
}

// MARK: - Jellyfin Metadata
struct JellyfinMovieMetadata: Codable, Sendable {
    let id: String
    let name: String
    let originalTitle: String?
    let overview: String?
    let productionYear: Int?
    let runTimeTicks: Int64?
    let genres: [String]
    let people: [JellyfinPerson]
    let mediaStreams: [JellyfinMediaStream]
    let providerIds: [String: String]?
    let studios: [JellyfinStudio]?
    let imageBlurHashes: [String: [String: String]]?
    let userData: JellyfinUserData?
    let remoteTrailers: [MediaUrl]?
    let dateCreated: Date?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case originalTitle = "OriginalTitle"
        case overview = "Overview"
        case productionYear = "ProductionYear"
        case runTimeTicks = "RunTimeTicks"
        case genres = "Genres"
        case people = "People"
        case mediaStreams = "MediaStreams"
        case providerIds = "ProviderIds"
        case studios = "Studios"
        case imageBlurHashes = "ImageBlurHashes"
        case userData = "UserData"
        case remoteTrailers = "RemoteTrailers"
        case dateCreated = "DateCreated"
    }

    init(
        id: String,
        name: String,
        originalTitle: String?,
        overview: String?,
        productionYear: Int?,
        runTimeTicks: Int64?,
        genres: [String],
        people: [JellyfinPerson],
        mediaStreams: [JellyfinMediaStream],
        providerIds: [String: String]?,
        studios: [JellyfinStudio]?,
        imageBlurHashes: [String: [String: String]]?,
        userData: JellyfinUserData?,
        remoteTrailers: [MediaUrl]?,
        dateCreated: Date?
    ) {
        self.id = id
        self.name = name
        self.originalTitle = originalTitle
        self.overview = overview
        self.productionYear = productionYear
        self.runTimeTicks = runTimeTicks
        self.genres = genres
        self.people = people
        self.mediaStreams = mediaStreams
        self.providerIds = providerIds
        self.studios = studios
        self.imageBlurHashes = imageBlurHashes
        self.userData = userData
        self.remoteTrailers = remoteTrailers
        self.dateCreated = dateCreated
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.originalTitle = try c.decodeIfPresent(String.self, forKey: .originalTitle)
        self.overview = try c.decodeIfPresent(String.self, forKey: .overview)
        self.productionYear = try c.decodeIfPresent(Int.self, forKey: .productionYear)
        self.runTimeTicks = try c.decodeIfPresent(Int64.self, forKey: .runTimeTicks)
        self.genres = try c.decodeIfPresent([String].self, forKey: .genres) ?? []
        self.people = try c.decodeIfPresent([JellyfinPerson].self, forKey: .people) ?? []
        self.mediaStreams = try c.decodeIfPresent([JellyfinMediaStream].self, forKey: .mediaStreams) ?? []
        self.providerIds = try c.decodeIfPresent([String: String].self, forKey: .providerIds)
        self.studios = try c.decodeIfPresent([JellyfinStudio].self, forKey: .studios)
        self.imageBlurHashes = try c.decodeIfPresent([String: [String: String]].self, forKey: .imageBlurHashes)
        self.userData = try c.decodeIfPresent(JellyfinUserData.self, forKey: .userData)
        self.remoteTrailers = try c.decodeIfPresent([MediaUrl].self, forKey: .remoteTrailers)
        if let dc = try c.decodeIfPresent(String.self, forKey: .dateCreated) {
            self.dateCreated = Date.from(iso8601: dc)
        } else {
            self.dateCreated = nil
        }
    }
    
    var runtimeMinutes: Int? {
        guard let ticks = runTimeTicks else { return nil }
        return Int(ticks / 600_000_000) // Convert from ticks to minutes
    }
    
    var director: String? {
        people.first { $0.type == "Director" }?.name
    }
    
    var cast: [String] {
        people.filter { $0.type == "Actor" }.prefix(10).map(\.name)
    }
}

struct JellyfinPerson: Codable, Sendable {
    let name: String
    let id: String
    let role: String?
    let type: String
    let primaryImageTag: String?

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case id = "Id"
        case role = "Role"
        case type = "Type"
        case primaryImageTag = "PrimaryImageTag"
    }
}

struct JellyfinMediaStream: Codable, Sendable {
    let codec: String?
    let type: String
    let index: Int
    let title: String?
    let language: String?
    let isForced: Bool?
    let isDefault: Bool?

    enum CodingKeys: String, CodingKey {
        case codec = "Codec"
        case type = "Type"
        case index = "Index"
        case title = "Title"
        case language = "Language"
        case isForced = "IsForced"
        case isDefault = "IsDefault"
    }
}

struct JellyfinUserData: Codable, Sendable {
    let played: Bool
    let playbackPositionTicks: Int64
    let playCount: Int
    let isFavorite: Bool
    let lastPlayedDate: String?

    enum CodingKeys: String, CodingKey {
        case played = "Played"
        case playbackPositionTicks = "PlaybackPositionTicks"
        case playCount = "PlayCount"
        case isFavorite = "IsFavorite"
        case lastPlayedDate = "LastPlayedDate"
    }
}

struct JellyfinStudio: Codable, Sendable {
    let id: String
    let name: String

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
    }
}

// MARK: - Response DTOs
struct MovieResponse: Codable, Sendable {
    let id: UUID?
    let jellyfinId: String
    let title: String
    let posterUrl: String?
    let isWatched: Bool
    let tags: [TagResponse]
    
    init(movie: Movie, tags: [Tag] = []) {
        self.id = movie.id
        self.jellyfinId = movie.jellyfinId
        self.title = movie.title
        self.posterUrl = movie.posterUrl
        self.isWatched = movie.jellyfinMetadata?.userData?.played ?? false
        self.tags = tags.map(TagResponse.init)
    }
}

struct MinimalTagResponse: Codable, Sendable {
    let slug: String
    let title: String
}

extension MinimalTagResponse {
    init(tag: Tag) {
        self.slug = tag.slug
        self.title = tag.title
    }
}

struct TagResponse: Codable, Sendable {
    let id: UUID?
    let slug: String
    let title: String
    let description: String
    let usageCount: Int
    let createdAt: Date?
    
    init(tag: Tag) {
        self.id = tag.id
        self.slug = tag.slug
        self.title = tag.title
        self.description = tag.description
        self.usageCount = tag.usageCount
        self.createdAt = tag.createdAt
    }
}

// MARK: - Client DTOs
struct ClientMovieResponse: Codable, Sendable {
    let id: UUID?
    let jellyfinId: String
    let title: String
    let year: Int?
    let runtime: String?
    let runtimeMinutes: Int?
    let description: String?
    let images: ClientImages
    let tags: [MinimalTagResponse]
    let imdbId: String?
    let isWatched: Bool
    let progressMs: Int?
    let progressPercent: Float?
    let trailerUrl: String?
    let addedAt: Date?
}

struct ClientImages: Codable, Sendable {
    let poster: String?
    let backdrop: String?
    let titleLogo: String?
}

// MARK: - Cast/People DTOs
struct PersonResponse: Codable, Sendable {
    let id: String
    let name: String
    let role: String?
    let type: String
    let imageUrl: String?
}

struct CastResponse: Codable, Sendable {
    let people: [PersonResponse]
}






struct ClientMoviesListResponse: Codable, Sendable {
    let movies: [ClientMovieResponse]
    let totalCount: Int
}

struct SuccessResponse: Codable, Sendable { let success: Bool }

// MARK: - OMDb Cache DTOs
struct OmdbCacheEntry: Codable, Sendable {
    let imdbId: String
    let ratings: [OmdbRating]
    let fetchedAt: Date
}

struct OmdbRating: Codable, Sendable { let Source: String; let Value: String }

// MARK: - Client Timeline DTOs
struct ClientTimelineItem: Codable, Sendable {
    let year: ClientTimelineYear
    let movies: [ClientMovieResponse]
}

enum ClientTimelineYear: Codable, Sendable {
    case known(Int)
    case unknown
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intVal = try? container.decode(Int.self) {
            self = .known(intVal)
            return
        }
        let strVal = try container.decode(String.self)
        self = strVal.lowercased() == "unknown" ? .unknown : .known(Int(strVal) ?? 0)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .known(let y):
            try container.encode(y)
        case .unknown:
            try container.encode("unknown")
        }
    }
}

// MARK: - Request DTOs
struct UpdateMovieTagsRequest: Codable, Sendable {
    let tagSlugs: [String]
    let replaceAll: Bool // If true, replace all tags. If false, add to existing
    
    func validate() throws {
        guard tagSlugs.count <= 5 else {
            throw ValidationError("Maximum 5 tags allowed per movie")
        }
        

        // Check for duplicates
        let uniqueTags = Set(tagSlugs)
        guard uniqueTags.count == tagSlugs.count else {
            throw ValidationError("Duplicate tags are not allowed")
        }
    }
}

struct AutoTagRequest: Codable, Sendable {
    let provider: String? // "openai", "anthropic", "gemini", or nil/"auto" to auto-pick
    let suggestionsOnly: Bool // If true, return suggestions without applying
    let customPrompt: String?
}

struct AutoTagResponse: Codable, Sendable {
    let suggestions: [String]
    let confidence: Float
    let reasoning: String?
}

struct ExportMovieTags: Codable, Sendable {
    let title: String
    let tags: [String]
}

struct ValidationError: Error, CustomStringConvertible {
    let message: String
    
    init(_ message: String) {
        self.message = message
    }
    
    var description: String { message }
}


// Extend MoodBucket to optionally include descriptive keywords used to steer LLM
extension MoodBucket {
    var tagsKeywords: [String] { tags ?? [] }
}
