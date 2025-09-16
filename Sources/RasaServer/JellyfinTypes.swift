import Foundation

// MARK: - Core Jellyfin Types

struct JellyfinItemsResponse: Codable, Sendable {
    let items: [BaseItemDto]?
    let totalRecordCount: Int?
    let startIndex: Int?
    
    enum CodingKeys: String, CodingKey {
        case items = "Items"
        case totalRecordCount = "TotalRecordCount"
        case startIndex = "StartIndex"
    }
}

struct BaseItemDto: Codable, Sendable {
    let name: String?
    let serverId: String?
    let id: String?
    let etag: String?
    let sourceType: String?
    let playlistItemId: String?
    let dateCreated: String?
    let dateLastMediaAdded: String?
    let extraType: String?
    let airsBeforeSeasonNumber: Int?
    let airsAfterSeasonNumber: Int?
    let airsBeforeEpisodeNumber: Int?
    let canDelete: Bool?
    let canDownload: Bool?
    let hasSubtitles: Bool?
    let preferredMetadataLanguage: String?
    let preferredMetadataCountryCode: String?
    let supportsSync: Bool?
    let container: String?
    let sortName: String?
    let forcedSortName: String?
    let video3DFormat: String?
    let premiereDate: String?
    let externalUrls: [ExternalUrl]?
    let mediaSources: [MediaSourceInfo]?
    let criticRating: Double?
    let productionLocations: [String]?
    let path: String?
    let enableMediaSourceDisplay: Bool?
    let officialRating: String?
    let customRating: String?
    let channelId: String?
    let channelName: String?
    let overview: String?
    let taglines: [String]?
    let genres: [String]?
    let communityRating: Double?
    let cumulativeRunTimeTicks: Int64?
    let runTimeTicks: Int64?
    let playAccess: String?
    let aspectRatio: String?
    let productionYear: Int?
    let isPlaceHolder: Bool?
    let number: String?
    let channelNumber: String?
    let indexNumber: Int?
    let indexNumberEnd: Int?
    let parentIndexNumber: Int?
    let remoteTrailers: [MediaUrl]?
    let providerIds: [String: String]?
    let isHD: Bool?
    let isFolder: Bool?
    let parentId: String?
    let type: String?
    let people: [BaseItemPerson]?
    let studios: [NameGuidPair]?
    let genreItems: [NameGuidPair]?
    let parentLogoItemId: String?
    let parentBackdropItemId: String?
    let parentBackdropImageTags: [String]?
    let localTrailerCount: Int?
    let userData: UserItemDataDto?
    let recursiveItemCount: Int?
    let childCount: Int?
    let seriesName: String?
    let seriesId: String?
    let seasonId: String?
    let specialFeatureCount: Int?
    let displayPreferencesId: String?
    let status: String?
    let airTime: String?
    let airDays: [String]?
    let tags: [String]?
    let primaryImageAspectRatio: Double?
    let artists: [String]?
    let artistItems: [NameGuidPair]?
    let album: String?
    let collectionType: String?
    let displayOrder: String?
    let albumId: String?
    let albumPrimaryImageTag: String?
    let seriesPrimaryImageTag: String?
    let albumArtist: String?
    let albumArtists: [NameGuidPair]?
    let seasonName: String?
    let mediaStreams: [MediaStream]?
    let videoType: String?
    let partCount: Int?
    let mediaSourceCount: Int?
    let imageTags: [String: String]?
    let backdropImageTags: [String]?
    let screenshotImageTags: [String]?
    let parentLogoImageTag: String?
    let parentArtItemId: String?
    let parentArtImageTag: String?
    let seriesThumbImageTag: String?
    let imageBlurHashes: [String: [String: String]]?
    let seriesStudio: String?
    let parentThumbItemId: String?
    let parentThumbImageTag: String?
    let parentPrimaryImageItemId: String?
    let parentPrimaryImageTag: String?
    let chapters: [ChapterInfo]?
    let locationType: String?
    let isoType: String?
    let mediaType: String?
    let endDate: String?
    let lockedFields: [String]?
    let trailerCount: Int?
    let movieCount: Int?
    let seriesCount: Int?
    let programCount: Int?
    let episodeCount: Int?
    let songCount: Int?
    let albumCount: Int?
    let artistCount: Int?
    let musicVideoCount: Int?
    let lockData: Bool?
    let width: Int?
    let height: Int?
    let cameraMake: String?
    let cameraModel: String?
    let software: String?
    let exposureTime: Double?
    let focalLength: Double?
    let imageOrientation: String?
    let aperture: Double?
    let shutterSpeed: Double?
    let latitude: Double?
    let longitude: Double?
    let altitude: Double?
    let isoSpeedRating: Int?
    let seriesTimerId: String?
    let programId: String?
    let channelPrimaryImageTag: String?
    let startDate: String?
    let completionPercentage: Double?
    let isRepeat: Bool?
    let episodeTitle: String?
    let channelType: String?
    let audio: String?
    let isMovie: Bool?
    let isSports: Bool?
    let isSeries: Bool?
    let isLive: Bool?
    let isNews: Bool?
    let isKids: Bool?
    let isPremiere: Bool?
    let timerId: String?
    let currentProgram: String? // Simplified to avoid circular reference
    let originalTitle: String?
}

struct ExternalUrl: Codable, Sendable {
    let name: String?
    let url: String?
}

struct MediaSourceInfo: Codable, Sendable {
    let `protocol`: String?
    let id: String?
    let path: String?
    let encoderPath: String?
    let encoderProtocol: String?
    let type: String?
    let container: String?
    let size: Int64?
    let name: String?
    let isRemote: Bool?
    let eTag: String?
    let runTimeTicks: Int64?
    let readAtNativeFramerate: Bool?
    let ignoreDts: Bool?
    let ignoreIndex: Bool?
    let genPtsInput: Bool?
    let supportsTranscoding: Bool?
    let supportsDirectStream: Bool?
    let supportsDirectPlay: Bool?
    let isInfiniteStream: Bool?
    let requiresOpening: Bool?
    let openToken: String?
    let requiresClosing: Bool?
    let liveStreamId: String?
    let bufferMs: Int?
    let requiresLooping: Bool?
    let supportsProbing: Bool?
    let videoType: String?
    let isoType: String?
    let video3DFormat: String?
    let mediaStreams: [MediaStream]?
    let mediaAttachments: [MediaAttachment]?
    let formats: [String]?
    let bitrate: Int?
    let timestamp: String?
    let requiredHttpHeaders: [String: String]?
    let transcodingUrl: String?
    let transcodingSubProtocol: String?
    let transcodingContainer: String?
    let analyzeDurationMs: Int?
    let defaultAudioStreamIndex: Int?
    let defaultSubtitleStreamIndex: Int?
}

struct MediaUrl: Codable, Sendable {
    let url: String?
    let name: String?
}

struct BaseItemPerson: Codable, Sendable {
    let name: String?
    let id: String?
    let role: String?
    let type: String?
    let primaryImageTag: String?
}

struct NameGuidPair: Codable, Sendable {
    let name: String?
    let id: String?
}

struct UserItemDataDto: Codable, Sendable {
    let rating: Double?
    let playedPercentage: Double?
    let unplayedItemCount: Int?
    let playbackPositionTicks: Int64?
    let playCount: Int?
    let isFavorite: Bool?
    let likes: Bool?
    let lastPlayedDate: String?
    let played: Bool?
    let key: String?
    let itemId: String?
}

struct MediaStream: Codable, Sendable {
    let codec: String?
    let codecTag: String?
    let language: String?
    let colorRange: String?
    let colorSpace: String?
    let colorTransfer: String?
    let colorPrimaries: String?
    let dvVersionMajor: Int?
    let dvVersionMinor: Int?
    let dvProfile: Int?
    let dvLevel: Int?
    let rpuPresentFlag: Int?
    let elPresentFlag: Int?
    let blPresentFlag: Int?
    let dvBlSignalCompatibilityId: Int?
    let comment: String?
    let timeBase: String?
    let codecTimeBase: String?
    let title: String?
    let videoRange: String?
    let videoRangeType: String?
    let videoDoViTitle: String?
    let localizedUndefined: String?
    let localizedDefault: String?
    let localizedForced: String?
    let localizedExternal: String?
    let displayTitle: String?
    let nalLengthSize: String?
    let isInterlaced: Bool?
    let isAVC: Bool?
    let channelLayout: String?
    let bitRate: Int?
    let bitDepth: Int?
    let refFrames: Int?
    let packetLength: Int?
    let channels: Int?
    let sampleRate: Int?
    let isDefault: Bool?
    let isForced: Bool?
    let height: Int?
    let width: Int?
    let averageFrameRate: Double?
    let realFrameRate: Double?
    let profile: String?
    let type: String?
    let aspectRatio: String?
    let index: Int?
    let score: Int?
    let isExternal: Bool?
    let deliveryMethod: String?
    let deliveryUrl: String?
    let isExternalUrl: Bool?
    let isTextSubtitleStream: Bool?
    let supportsExternalStream: Bool?
    let path: String?
    let pixelFormat: String?
    let level: Double?
    let isAnamorphic: Bool?
}

struct MediaAttachment: Codable, Sendable {
    let codec: String?
    let codecTag: String?
    let comment: String?
    let index: Int?
    let fileName: String?
    let mimeType: String?
    let deliveryUrl: String?
}

struct ChapterInfo: Codable, Sendable {
    let startPositionTicks: Int64?
    let name: String?
    let imagePath: String?
    let imageDateModified: String?
    let imageTag: String?
}

// MARK: - Image Types

enum ImageType: String, Codable, Sendable {
    case primary = "Primary"
    case art = "Art"
    case backdrop = "Backdrop"
    case banner = "Banner"
    case logo = "Logo"
    case thumb = "Thumb"
    case disc = "Disc"
    case box = "Box"
    case screenshot = "Screenshot"
    case menu = "Menu"
    case chapter = "Chapter"
    case boxRear = "BoxRear"
    case profile = "Profile"
}

// MARK: - Authentication Types

struct AuthenticationResult: Codable, Sendable {
    let user: UserDto?
    let sessionInfo: SessionInfo?
    let accessToken: String?
    let serverId: String?
    
    enum CodingKeys: String, CodingKey {
        case user = "User"
        case sessionInfo = "SessionInfo"
        case accessToken = "AccessToken"
        case serverId = "ServerId"
    }
}

struct UserDto: Codable, Sendable {
    let name: String?
    let serverId: String?
    let id: String?
    let primaryImageTag: String?
    let hasPassword: Bool?
    let hasConfiguredPassword: Bool?
    let hasConfiguredEasyPassword: Bool?
    let enableAutoLogin: Bool?
    let lastLoginDate: String?
    let lastActivityDate: String?
    let configuration: UserConfiguration?
    let policy: UserPolicy?
    
    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case serverId = "ServerId"
        case id = "Id"
        case primaryImageTag = "PrimaryImageTag"
        case hasPassword = "HasPassword"
        case hasConfiguredPassword = "HasConfiguredPassword"
        case hasConfiguredEasyPassword = "HasConfiguredEasyPassword"
        case enableAutoLogin = "EnableAutoLogin"
        case lastLoginDate = "LastLoginDate"
        case lastActivityDate = "LastActivityDate"
        case configuration = "Configuration"
        case policy = "Policy"
    }
}

struct SessionInfo: Codable, Sendable {
    let playState: PlayerStateInfo?
    let additionalUsers: [SessionUserInfo]?
    let capabilities: ClientCapabilities?
    let remoteEndPoint: String?
    let playableMediaTypes: [String]?
    let id: String?
    let userId: String?
    let userName: String?
    let client: String?
    let lastActivityDate: String?
    let lastPlaybackCheckIn: String?
    let deviceName: String?
    let deviceType: String?
    let nowPlayingItem: String? // Simplified to avoid circular reference
    let fullNowPlayingItem: String? // Simplified to avoid circular reference
    let nowViewingItem: String? // Simplified to avoid circular reference
    let deviceId: String?
    let applicationVersion: String?
    let transcodingInfo: TranscodingInfo?
    let isActive: Bool?
    let supportsMediaControl: Bool?
    let supportsRemoteControl: Bool?
    let nowPlayingQueue: [QueueItem]?
    let nowPlayingQueueFullItems: [String]? // Simplified to avoid circular reference
    let hasCustomDeviceName: Bool?
    let playlistItemId: String?
    let serverId: String?
    let userPrimaryImageTag: String?
    let supportedCommands: [String]?
    
    enum CodingKeys: String, CodingKey {
        case playState = "PlayState"
        case additionalUsers = "AdditionalUsers"
        case capabilities = "Capabilities"
        case remoteEndPoint = "RemoteEndPoint"
        case playableMediaTypes = "PlayableMediaTypes"
        case id = "Id"
        case userId = "UserId"
        case userName = "UserName"
        case client = "Client"
        case lastActivityDate = "LastActivityDate"
        case lastPlaybackCheckIn = "LastPlaybackCheckIn"
        case deviceName = "DeviceName"
        case deviceType = "DeviceType"
        case nowPlayingItem = "NowPlayingItem"
        case fullNowPlayingItem = "FullNowPlayingItem"
        case nowViewingItem = "NowViewingItem"
        case deviceId = "DeviceId"
        case applicationVersion = "ApplicationVersion"
        case transcodingInfo = "TranscodingInfo"
        case isActive = "IsActive"
        case supportsMediaControl = "SupportsMediaControl"
        case supportsRemoteControl = "SupportsRemoteControl"
        case nowPlayingQueue = "NowPlayingQueue"
        case nowPlayingQueueFullItems = "NowPlayingQueueFullItems"
        case hasCustomDeviceName = "HasCustomDeviceName"
        case playlistItemId = "PlaylistItemId"
        case serverId = "ServerId"
        case userPrimaryImageTag = "UserPrimaryImageTag"
        case supportedCommands = "SupportedCommands"
    }
}

// MARK: - Playback Reporting Types

enum PlayMethod: String, Codable, Sendable {
    case transcode = "Transcode"
    case directStream = "DirectStream"
    case directPlay = "DirectPlay"
}

struct PlaybackStartInfo: Codable, Sendable {
    let audioStreamIndex: Int?
    let canSeek: Bool?
    let itemID: String?
    let mediaSourceID: String?
    let playMethod: PlayMethod?
    let playSessionID: String?
    let positionTicks: Int64?
    let sessionID: String?
    let subtitleStreamIndex: Int?
    
    enum CodingKeys: String, CodingKey {
        case audioStreamIndex = "AudioStreamIndex"
        case canSeek = "CanSeek"
        case itemID = "ItemId"
        case mediaSourceID = "MediaSourceId"
        case playMethod = "PlayMethod"
        case playSessionID = "PlaySessionId"
        case positionTicks = "PositionTicks"
        case sessionID = "SessionId"
        case subtitleStreamIndex = "SubtitleStreamIndex"
    }
}

struct PlaybackProgressInfo: Codable, Sendable {
    let isPaused: Bool?
    let itemID: String?
    let mediaSourceID: String?
    let playSessionID: String?
    let positionTicks: Int64?
    let sessionID: String?
    
    enum CodingKeys: String, CodingKey {
        case isPaused = "IsPaused"
        case itemID = "ItemId"
        case mediaSourceID = "MediaSourceId"
        case playSessionID = "PlaySessionId"
        case positionTicks = "PositionTicks"
        case sessionID = "SessionId"
    }
}

struct PlaybackStopInfo: Codable, Sendable {
    let itemID: String?
    let mediaSourceID: String?
    let playSessionID: String?
    let positionTicks: Int64?
    let sessionID: String?
    
    enum CodingKeys: String, CodingKey {
        case itemID = "ItemId"
        case mediaSourceID = "MediaSourceId"
        case playSessionID = "PlaySessionId"
        case positionTicks = "PositionTicks"
        case sessionID = "SessionId"
    }
}

struct QueueItem: Codable, Sendable {
    let id: String?
    let playlistItemId: String?
}

// MARK: - Supporting Types (simplified versions)

struct PlayerStateInfo: Codable, Sendable {
    let positionTicks: Int64?
    let canSeek: Bool?
    let isPaused: Bool?
    let isMuted: Bool?
    let volumeLevel: Int?
    let audioStreamIndex: Int?
    let subtitleStreamIndex: Int?
    let mediaSourceId: String?
    let playMethod: String?
    let repeatMode: String?
}

struct SessionUserInfo: Codable, Sendable {
    let userId: String?
    let userName: String?
}

struct ClientCapabilities: Codable, Sendable {
    let playableMediaTypes: [String]?
    let supportedCommands: [String]?
    let supportsMediaControl: Bool?
    let supportsContentUploading: Bool?
    let messageCallbackUrl: String?
    let supportsPersistentIdentifier: Bool?
    let supportsSync: Bool?
    let deviceProfile: DeviceProfile?
    let appStoreUrl: String?
    let iconUrl: String?
}

struct DeviceProfile: Codable, Sendable {
    let name: String?
    let id: String?
    let identification: DeviceIdentification?
    let friendlyName: String?
    let manufacturer: String?
    let manufacturerUrl: String?
    let modelName: String?
    let modelDescription: String?
    let modelNumber: String?
    let modelUrl: String?
    let serialNumber: String?
    let enableAlbumArtInDidl: Bool?
    let enableSingleAlbumArtLimit: Bool?
    let enableSingleSubtitleLimit: Bool?
    let supportedMediaTypes: String?
    let userId: String?
    let albumArtPn: String?
    let maxAlbumArtWidth: Int?
    let maxAlbumArtHeight: Int?
    let maxIconWidth: Int?
    let maxIconHeight: Int?
    let maxStreamingBitrate: Int64?
    let maxStaticBitrate: Int64?
    let musicStreamingTranscodingBitrate: Int?
    let maxStaticMusicBitrate: Int?
    let sonyAggregationFlags: String?
    let protocolInfo: String?
    let timelineOffsetSeconds: Int?
    let requiresPlainVideoItems: Bool?
    let requiresPlainFolders: Bool?
    let enableMSMediaReceiverRegistrar: Bool?
    let ignoreTranscodeByteRangeRequests: Bool?
    let xmlRootAttributes: [XmlAttribute]?
    let directPlayProfiles: [DirectPlayProfile]?
    let transcodingProfiles: [TranscodingProfile]?
    let containerProfiles: [ContainerProfile]?
    let codecProfiles: [CodecProfile]?
    let responseProfiles: [ResponseProfile]?
    let subtitleProfiles: [SubtitleProfile]?
}

struct DeviceIdentification: Codable, Sendable {
    let friendlyName: String?
    let modelNumber: String?
    let serialNumber: String?
    let modelName: String?
    let modelDescription: String?
    let modelUrl: String?
    let manufacturer: String?
    let manufacturerUrl: String?
    let headers: [HttpHeaderInfo]?
}

struct XmlAttribute: Codable, Sendable {
    let name: String?
    let value: String?
}

struct DirectPlayProfile: Codable, Sendable {
    let container: String?
    let audioCodec: String?
    let videoCodec: String?
    let type: String?
}

struct TranscodingProfile: Codable, Sendable {
    let container: String?
    let type: String?
    let videoCodec: String?
    let audioCodec: String?
    let `protocol`: String?
    let estimateContentLength: Bool?
    let enableMpegtsM2TsMode: Bool?
    let transcodeSeekInfo: String?
    let copyTimestamps: Bool?
    let context: String?
    let enableSubtitlesInManifest: Bool?
    let maxAudioChannels: String?
    let minSegments: Int?
    let segmentLength: Int?
    let breakOnNonKeyFrames: Bool?
}

struct ContainerProfile: Codable, Sendable {
    let type: String?
    let conditions: [ProfileCondition]?
    let container: String?
}

struct CodecProfile: Codable, Sendable {
    let type: String?
    let conditions: [ProfileCondition]?
    let applyConditions: [ProfileCondition]?
    let codec: String?
    let container: String?
}

struct ResponseProfile: Codable, Sendable {
    let container: String?
    let audioCodec: String?
    let videoCodec: String?
    let type: String?
    let orgPn: String?
    let mimeType: String?
    let conditions: [ProfileCondition]?
}

struct SubtitleProfile: Codable, Sendable {
    let format: String?
    let method: String?
    let didlMode: String?
    let language: String?
    let container: String?
}

struct ProfileCondition: Codable, Sendable {
    let condition: String?
    let property: String?
    let value: String?
    let isRequired: Bool?
}

struct HttpHeaderInfo: Codable, Sendable {
    let name: String?
    let value: String?
    let match: String?
}

struct TranscodingInfo: Codable, Sendable {
    let audioCodec: String?
    let videoCodec: String?
    let container: String?
    let isVideoDirect: Bool?
    let isAudioDirect: Bool?
    let bitrate: Int?
    let framerate: Float?
    let completionPercentage: Double?
    let width: Int?
    let height: Int?
    let audioChannels: Int?
    let hardwareAccelerationType: String?
    let transcodeReasons: [String]?
}

struct UserConfiguration: Codable, Sendable {
    let audioLanguagePreference: String?
    let playDefaultAudioTrack: Bool?
    let subtitleLanguagePreference: String?
    let displayMissingEpisodes: Bool?
    let groupedFolders: [String]?
    let subtitleMode: String?
    let displayCollectionsView: Bool?
    let enableLocalPassword: Bool?
    let orderedViews: [String]?
    let latestItemsExcludes: [String]?
    let myMediaExcludes: [String]?
    let hidePlayedInLatest: Bool?
    let rememberAudioSelections: Bool?
    let rememberSubtitleSelections: Bool?
    let enableNextEpisodeAutoPlay: Bool?
}

struct UserPolicy: Codable, Sendable {
    let isAdministrator: Bool?
    let isHidden: Bool?
    let isDisabled: Bool?
    let maxParentalRating: Int?
    let blockedTags: [String]?
    let enableUserPreferenceAccess: Bool?
    let accessSchedules: [AccessSchedule]?
    let blockUnratedItems: [String]?
    let enableRemoteControlOfOtherUsers: Bool?
    let enableSharedDeviceControl: Bool?
    let enableRemoteAccess: Bool?
    let enableLiveTvManagement: Bool?
    let enableLiveTvAccess: Bool?
    let enableMediaPlayback: Bool?
    let enableAudioPlaybackTranscoding: Bool?
    let enableVideoPlaybackTranscoding: Bool?
    let enablePlaybackRemuxing: Bool?
    let forceRemoteSourceTranscoding: Bool?
    let enableContentDeletion: Bool?
    let enableContentDeletionFromFolders: [String]?
    let enableContentDownloading: Bool?
    let enableSyncTranscoding: Bool?
    let enableMediaConversion: Bool?
    let enabledDevices: [String]?
    let enableAllDevices: Bool?
    let enabledChannels: [String]?
    let enableAllChannels: Bool?
    let enabledFolders: [String]?
    let enableAllFolders: Bool?
    let invalidLoginAttemptCount: Int?
    let loginAttemptsBeforeLockout: Int?
    let maxActiveSessions: Int?
    let enablePublicSharing: Bool?
    let blockedMediaFolders: [String]?
    let blockedChannels: [String]?
    let remoteClientBitrateLimit: Int?
    let authenticationProviderId: String?
    let passwordResetProviderId: String?
    let syncPlayAccess: String?
}

struct AccessSchedule: Codable, Sendable {
    let id: Int?
    let userId: String?
    let dayOfWeek: String?
    let startHour: Double?
    let endHour: Double?
}
