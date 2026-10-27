import Foundation

/// Main Supabase service for API interactions
class SupabaseService {
    static let shared = SupabaseService()

    private let baseURL: URL
    private let anonKey: String
    private var authToken: String?

    private init() {
        guard let url = URL(string: Config.supabaseURL) else {
            fatalError("Invalid Supabase URL in Config")
        }
        self.baseURL = url
        self.anonKey = Config.supabaseAnonKey
    }

    // MARK: - Auth Token Management

    func setAuthToken(_ token: String?) {
        self.authToken = token
    }

    // MARK: - Request Building

    private func buildRequest(
        endpoint: String,
        method: String = "GET",
        body: Data? = nil,
        queryParams: [String: String]? = nil
    ) -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(endpoint), resolvingAgainstBaseURL: true)!

        if let queryParams = queryParams {
            components.queryItems = queryParams.map { URLQueryItem(name: $0.key, value: $0.value) }
        }

        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")

        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        }

        if let body = body {
            request.httpBody = body
        }

        return request
    }

    // MARK: - REST API

    func fetch<T: Decodable>(
        from table: String,
        select: String = "*",
        filters: [String: String] = [:],
        order: String? = nil,
        limit: Int? = nil
    ) async throws -> [T] {
        var queryParams = filters
        queryParams["select"] = select

        if let order = order {
            queryParams["order"] = order
        }

        if let limit = limit {
            queryParams["limit"] = String(limit)
        }

        let request = buildRequest(
            endpoint: "rest/v1/\(table)",
            queryParams: queryParams
        )

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw SupabaseError.requestFailed
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            let formatters: [ISO8601DateFormatter] = [
                {
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    return formatter
                }(),
                {
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime]
                    return formatter
                }()
            ]

            for formatter in formatters {
                if let date = formatter.date(from: dateString) {
                    return date
                }
            }

            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date: \(dateString)")
        }

        return try decoder.decode([T].self, from: data)
    }

    func insert<T: Codable>(into table: String, values: T) async throws -> T {
        let encoder = JSONEncoder()
        // Postgres rejects Foundation's default Date encoding (seconds since
        // 2001 as a number) for timestamptz columns with a 400.
        encoder.dateEncodingStrategy = .iso8601
        let body = try encoder.encode(values)

        var request = buildRequest(
            endpoint: "rest/v1/\(table)",
            method: "POST",
            body: body
        )
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw SupabaseError.requestFailed
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let results = try decoder.decode([T].self, from: data)
        guard let result = results.first else {
            throw SupabaseError.noData
        }

        return result
    }

    func update(
        table: String,
        id: UUID,
        values: [String: Any]
    ) async throws {
        let body = try JSONSerialization.data(withJSONObject: values)

        let request = buildRequest(
            endpoint: "rest/v1/\(table)",
            method: "PATCH",
            body: body,
            queryParams: ["id": "eq.\(id.uuidString)"]
        )

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw SupabaseError.requestFailed
        }
    }

    func delete(from table: String, id: UUID) async throws {
        let request = buildRequest(
            endpoint: "rest/v1/\(table)",
            method: "DELETE",
            queryParams: ["id": "eq.\(id.uuidString)"]
        )

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw SupabaseError.requestFailed
        }
    }

    // MARK: - RPC (Remote Procedure Calls)

    func rpc<T: Decodable>(
        function: String,
        params: [String: Any] = [:]
    ) async throws -> T {
        let body = try JSONSerialization.data(withJSONObject: params)

        let request = buildRequest(
            endpoint: "rest/v1/rpc/\(function)",
            method: "POST",
            body: body
        )

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw SupabaseError.requestFailed
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return try decoder.decode(T.self, from: data)
    }

    // MARK: - Edge Functions

    func invokeFunction<T: Decodable>(
        name: String,
        body: [String: Any] = [:]
    ) async throws -> T {
        let bodyData = try JSONSerialization.data(withJSONObject: body)

        let request = buildRequest(
            endpoint: "functions/v1/\(name)",
            method: "POST",
            body: bodyData
        )

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw SupabaseError.requestFailed
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return try decoder.decode(T.self, from: data)
    }
}

// MARK: - Errors

enum SupabaseError: LocalizedError {
    case requestFailed
    case noData
    case unauthorized
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .requestFailed:
            return "The request failed. Please try again."
        case .noData:
            return "No data was returned from the server."
        case .unauthorized:
            return "You are not authorized to perform this action."
        case .invalidResponse:
            return "The server returned an invalid response."
        }
    }
}
