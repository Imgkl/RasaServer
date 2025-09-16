import Foundation

enum JellyfinError: Error, Sendable {
    case authenticationFailed(String)
    case requestFailed(String)
    case invalidResponse(String)
    case networkError(String)
    case decodingError(String)
    case invalidURL(String)
    case missingData(String)
    case serverError(Int, String)
    case httpError(Int, String)
    case timeout(String)
    case unauthorized
    case notFound
    case forbidden
    case badRequest(String)
    case internalServerError
    case serviceUnavailable
    case unknown(String)
}

extension JellyfinError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .httpError(let code, let message):
            return "HTTP Error (\(code)): \(message)"
        case .authenticationFailed(let message):
            return "Authentication failed: \(message)"
        case .invalidResponse:
            return "Invalid response from Jellyfin server"
        case .requestFailed(let message):
            return "Request failed: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .decodingError(let message):
            return "Decoding error: \(message)"
        case .invalidURL(let message):
            return "Invalid URL: \(message)"
        case .missingData(let message):
            return "Missing data: \(message)"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message)"
        case .timeout(let message):
            return "Timeout: \(message)"
        case .unauthorized:
            return "Unauthorized access"
        case .notFound:
            return "Resource not found"
        case .forbidden:
            return "Access forbidden"
        case .badRequest(let message):
            return "Bad request: \(message)"
        case .internalServerError:
            return "Internal server error"
        case .serviceUnavailable:
            return "Service unavailable"
        case .unknown(let message):
            return "Unknown error: \(message)"
        }
    }
}
