import Foundation
import FluentKit
import Hummingbird
import AsyncHTTPClient
import NIOCore
import HTTPTypes

// MARK: - Optional Extensions

extension Optional where Wrapped == String {
    var isEmptyOrNil: Bool {
        return self?.isEmpty ?? true
    }
}

extension Optional {
    func unwrap(orError error: Error) throws -> Wrapped {
        guard let value = self else { throw error }
        return value
    }
}

// MARK: - String Extensions

extension String {
    var slugified: String {
        return self
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "[^a-z0-9-]", with: "", options: .regularExpression)
    }
    
    func truncated(to length: Int, trailing: String = "...") -> String {
        return count > length ? String(prefix(length)) + trailing : self
    }
    
    var isValidUrl: Bool {
        guard let url = URL(string: self) else { return false }
        return url.scheme != nil && url.host != nil
    }
}

// MARK: - Collection Extensions

extension Collection {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

extension Array where Element == String {
    var nonEmpty: [String] {
        return filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

// MARK: - Date Extensions

extension Date {
    var iso8601String: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: self)
    }
    
    static func from(iso8601 string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string)
    }
    
    func timeAgo() -> String {
        let now = Date()
        let timeInterval = now.timeIntervalSince(self)
        
        if timeInterval < 60 {
            return "just now"
        } else if timeInterval < 3600 {
            let minutes = Int(timeInterval / 60)
            return "\(minutes) minute\(minutes == 1 ? "" : "s") ago"
        } else if timeInterval < 86400 {
            let hours = Int(timeInterval / 3600)
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        } else {
            let days = Int(timeInterval / 86400)
            return "\(days) day\(days == 1 ? "" : "s") ago"
        }
    }
}

// MARK: - HTTP Extensions

extension HTTPClientResponse {
    var bodyData: Data {
        get async throws {
            let buffer = try await body.collect(upTo: 10 * 1024 * 1024) // 10MB limit
            return Data(buffer.readableBytesView)
        }
    }
    
    func decodeJSON<T: Decodable>(as type: T.Type) async throws -> T {
        let data = try await bodyData
        return try JSONDecoder().decode(type, from: data)
    }
}

extension HTTPClient.Response {
    var isSuccessful: Bool {
        return (200..<300).contains(status.code)
    }
}

// MARK: - JSON Encoding/Decoding

extension Encodable {
    func toJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        return try encoder.encode(self)
    }
    
    func toJSONString() throws -> String {
        let data = try toJSON()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

extension Data {
    func decodeJSON<T: Decodable>(as type: T.Type) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: self)
    }
}

// MARK: - Response helpers

func responseBody(from data: Data) -> ResponseBody {
    var buffer = ByteBufferAllocator().buffer(capacity: data.count)
    buffer.writeBytes(data)
    return ResponseBody(byteBuffer: buffer)
}

func jsonResponse<T: Encodable>(_ value: T, status: HTTPResponse.Status = .ok) throws -> Response {
    let data = try value.toJSON()
    let body = responseBody(from: data)
    let headers = HTTPFields([
        HTTPField(name: .contentType, value: "application/json; charset=utf-8")
    ])
    return Response(status: status, headers: headers, body: body)
}

func textResponse(_ text: String, contentType: String = "text/plain; charset=utf-8", status: HTTPResponse.Status = .ok) -> Response {
    let data = Data(text.utf8)
    let body = responseBody(from: data)
    let headers = HTTPFields([
        HTTPField(name: .contentType, value: contentType)
    ])
    return Response(status: status, headers: headers, body: body)
}

// MARK: - URL Extensions

extension URL {
    func appendingQueryItem(name: String, value: String) -> URL {
        var components = URLComponents(url: self, resolvingAgainstBaseURL: false)
        var queryItems = components?.queryItems ?? []
        queryItems.append(URLQueryItem(name: name, value: value))
        components?.queryItems = queryItems
        return components?.url ?? self
    }
    
    func appendingQueryItems(_ items: [String: String]) -> URL {
        var result = self
        for (name, value) in items {
            result = result.appendingQueryItem(name: name, value: value)
        }
        return result
    }
}

// MARK: - Fluent Extensions

extension Model {
    func exists(on database: any Database) async throws -> Bool {
        guard let id = self.id else { return false }
        return try await Self.find(id, on: database) != nil
    }
}

// Removed invalid QueryBuilder extension; not needed

// MARK: - Validation Helpers

struct Validator {
    static func validateEmail(_ email: String) -> Bool {
        let emailRegex = "^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"
        let emailTest = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailTest.evaluate(with: email)
    }
    
    static func validateURL(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString) else { return false }
        return url.scheme != nil && url.host != nil
    }
    
    static func validateJellyfinURL(_ urlString: String) -> Bool {
        guard validateURL(urlString) else { return false }
        // Additional Jellyfin-specific validation could go here
        return true
    }
    
    static func validateAPIKey(_ key: String, provider: String) -> Bool {
        switch provider.lowercased() {
        case "anthropic":
            return key.hasPrefix("sk-ant-") && key.count > 20
        default:
            return !key.isEmpty
        }
    }
}

// MARK: - Error Handling

extension Error {
    var localizedDescription: String {
        if let localizedError = self as? LocalizedError {
            return localizedError.errorDescription ?? String(describing: self)
        }
        return String(describing: self)
    }
}

// MARK: - Async Extensions

extension Task where Success == Never, Failure == Never {
    static func sleep(seconds: Double) async throws {
        let nanoseconds = UInt64(seconds * 1_000_000_000)
        try await Task.sleep(nanoseconds: nanoseconds)
    }
}

// MARK: - Performance Helpers

struct PerformanceTimer {
    private let startTime: DispatchTime
    
    init() {
        startTime = DispatchTime.now()
    }
    
    var elapsed: TimeInterval {
        let endTime = DispatchTime.now()
        let nanoseconds = endTime.uptimeNanoseconds - startTime.uptimeNanoseconds
        return Double(nanoseconds) / 1_000_000_000.0
    }
    
    var elapsedMilliseconds: Double {
        return elapsed * 1000.0
    }
}

// MARK: - Logging Helpers

import Logging

extension Logger {
    func logPerformance<T>(_ operation: String, level: Logger.Level = .info, _ block: () async throws -> T) async rethrows -> T {
        let timer = PerformanceTimer()
        let result = try await block()
        self.log(level: level, "\(operation) completed in \(String(format: "%.2f", timer.elapsedMilliseconds))ms")
        return result
    }
}

// MARK: - Configuration Validation

extension JellybellyConfiguration {
    func validate() throws {
        // Validate required fields
        guard !jellyfinUrl.isEmpty else {
            throw ConfigurationError.missingField("jellyfin_url")
        }
        
        guard !jellyfinApiKey.isEmpty else {
            throw ConfigurationError.missingField("jellyfin_api_key")
        }
        
        guard !jellyfinUserId.isEmpty else {
            throw ConfigurationError.missingField("jellyfin_user_id")
        }
        
        // Validate Jellyfin URL format
        guard Validator.validateJellyfinURL(jellyfinUrl) else {
            throw ConfigurationError.invalidValue("jellyfin_url", "Invalid URL format")
        }
        
        // Validate port range
        guard (1...65535).contains(port) else {
            throw ConfigurationError.invalidValue("port", "Port must be between 1 and 65535")
        }
        
        // Validate API keys if provided (Anthropic only)
        if let anthropicKey = anthropicApiKey, !anthropicKey.isEmpty {
            guard Validator.validateAPIKey(anthropicKey, provider: "anthropic") else {
                throw ConfigurationError.invalidValue("anthropic_api_key", "Invalid Anthropic API key format")
            }
        }
        
        // Validate max tags
        guard (1...4).contains(maxAutoTags) else {
            throw ConfigurationError.invalidValue("max_auto_tags", "Must be between 1 and 4")
        }
    }
}

enum ConfigurationError: Error, CustomStringConvertible {
    case missingField(String)
    case invalidValue(String, String)
    
    var description: String {
        switch self {
        case .missingField(let field):
            return "Missing required configuration field: \(field)"
        case .invalidValue(let field, let reason):
            return "Invalid value for \(field): \(reason)"
        }
    }
}

// MARK: - Rate Limiting Helper

actor RateLimiter {
    private var lastRequestTime: DispatchTime = .now()
    private let minimumInterval: UInt64
    
    init(requestsPerSecond: Double) {
        self.minimumInterval = UInt64(1_000_000_000.0 / requestsPerSecond)
    }
    
    func waitIfNeeded() async {
        let now = DispatchTime.now()
        let timeSinceLastRequest = now.uptimeNanoseconds - lastRequestTime.uptimeNanoseconds
        
        if timeSinceLastRequest < minimumInterval {
            let waitTime = minimumInterval - timeSinceLastRequest
            try? await Task.sleep(nanoseconds: waitTime)
        }
        
        lastRequestTime = .now()
    }
}
