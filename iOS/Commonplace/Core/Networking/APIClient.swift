import Foundation

/// Generic API client for making HTTP requests
class APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = true

        self.session = URLSession(configuration: config)

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601

        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
    }

    // MARK: - Request Methods

    func get<T: Decodable>(
        url: URL,
        headers: [String: String] = [:]
    ) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        return try await perform(request)
    }

    func post<T: Decodable, B: Encodable>(
        url: URL,
        body: B,
        headers: [String: String] = [:]
    ) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)

        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        return try await perform(request)
    }

    func patch<B: Encodable>(
        url: URL,
        body: B,
        headers: [String: String] = [:]
    ) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)

        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.requestFailed
        }
    }

    func delete(
        url: URL,
        headers: [String: String] = [:]
    ) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.requestFailed
        }
    }

    // MARK: - Private

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            return try decoder.decode(T.self, from: data)
        case 401:
            throw APIError.unauthorized
        case 404:
            throw APIError.notFound
        case 400...499:
            throw APIError.clientError(httpResponse.statusCode)
        case 500...599:
            throw APIError.serverError(httpResponse.statusCode)
        default:
            throw APIError.unknown
        }
    }
}

// MARK: - API Errors

enum APIError: LocalizedError {
    case invalidResponse
    case requestFailed
    case unauthorized
    case notFound
    case clientError(Int)
    case serverError(Int)
    case decodingError
    case unknown

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .requestFailed:
            return "Request failed"
        case .unauthorized:
            return "Unauthorized. Please sign in again."
        case .notFound:
            return "Resource not found"
        case .clientError(let code):
            return "Client error: \(code)"
        case .serverError(let code):
            return "Server error: \(code)"
        case .decodingError:
            return "Failed to decode response"
        case .unknown:
            return "An unknown error occurred"
        }
    }
}
