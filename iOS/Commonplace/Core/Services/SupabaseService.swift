import Foundation

/// Main Supabase service for API interactions
class SupabaseService {
    static let shared = SupabaseService()

    private let baseURL: URL
    private let anonKey: String

    private init() {
        guard let url = URL(string: Config.supabaseURL) else {
            fatalError("Invalid Supabase URL in Config")
        }
        self.baseURL = url
        self.anonKey = Config.supabaseAnonKey
    }

    // MARK: - Request Building

    private func buildRequest(
        endpoint: String,
        method: String = "GET",
        body: Data? = nil,
        queryParams: [String: String]? = nil,
        headers: [String: String] = [:],
        token: String?
    ) -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(endpoint), resolvingAgainstBaseURL: true)!

        if let queryParams = queryParams {
            components.queryItems = queryParams.map { URLQueryItem(name: $0.key, value: $0.value) }
        }

        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token ?? anonKey)", forHTTPHeaderField: "Authorization")
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }

        if let body = body {
            request.httpBody = body
        }

        return request
    }

    /// Sends a request as the signed-in user (the anon key when signed out),
    /// with an access token that has not expired. A 401 means the token was
    /// revoked or expired early: refresh once and retry.
    private func send(
        endpoint: String,
        method: String = "GET",
        body: Data? = nil,
        queryParams: [String: String]? = nil,
        headers: [String: String] = [:]
    ) async throws -> Data {
        let signedIn = await SessionManager.shared.hasSession
        var token = signedIn ? try await SessionManager.shared.validAccessToken() : nil

        var (data, response) = try await URLSession.shared.data(for: buildRequest(
            endpoint: endpoint, method: method, body: body, queryParams: queryParams, headers: headers, token: token
        ))
        if signedIn, (response as? HTTPURLResponse)?.statusCode == 401 {
            token = try await SessionManager.shared.validAccessToken(forceRefresh: true)
            (data, response) = try await URLSession.shared.data(for: buildRequest(
                endpoint: endpoint, method: method, body: body, queryParams: queryParams, headers: headers, token: token
            ))
        }

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            // Edge Functions explain refusals the app acts on (a Pro-only
            // feature, a monthly limit) as {"error": ..., "code": ...}
            if let refusal = try? JSONDecoder().decode(FunctionRefusal.self, from: data) {
                throw SupabaseError.rejected(code: refusal.code, message: refusal.error)
            }
            throw SupabaseError.requestFailed
        }
        return data
    }

    private struct FunctionRefusal: Decodable {
        let error: String
        let code: String
    }

    /// Accepts timestamps with and without fractional seconds (Postgres and
    /// JavaScript's toISOString both add them; `.iso8601` rejects them)
    static func flexibleDateDecoder() -> JSONDecoder {
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
        return decoder
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

        let data = try await send(
            endpoint: "rest/v1/\(table)",
            queryParams: queryParams
        )

        let decoder = Self.flexibleDateDecoder()

        return try decoder.decode([T].self, from: data)
    }

    func insert<T: Codable>(into table: String, values: T) async throws -> T {
        let encoder = JSONEncoder()
        // Postgres rejects Foundation's default Date encoding (seconds since
        // 2001 as a number) for timestamptz columns with a 400.
        encoder.dateEncodingStrategy = .iso8601
        let body = try encoder.encode(values)

        let data = try await send(
            endpoint: "rest/v1/\(table)",
            method: "POST",
            body: body,
            headers: ["Prefer": "return=representation"]
        )

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

        _ = try await send(
            endpoint: "rest/v1/\(table)",
            method: "PATCH",
            body: body,
            queryParams: ["id": "eq.\(id.uuidString)"]
        )
    }

    func delete(from table: String, id: UUID) async throws {
        _ = try await send(
            endpoint: "rest/v1/\(table)",
            method: "DELETE",
            queryParams: ["id": "eq.\(id.uuidString)"]
        )
    }

    // MARK: - RPC (Remote Procedure Calls)

    func rpc<T: Decodable>(
        function: String,
        params: [String: Any] = [:]
    ) async throws -> T {
        let body = try JSONSerialization.data(withJSONObject: params)

        let data = try await send(
            endpoint: "rest/v1/rpc/\(function)",
            method: "POST",
            body: body
        )

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

        let data = try await send(
            endpoint: "functions/v1/\(name)",
            method: "POST",
            body: bodyData
        )

        return try Self.flexibleDateDecoder().decode(T.self, from: data)
    }
}

// MARK: - Errors

enum SupabaseError: LocalizedError {
    case requestFailed
    case noData
    case unauthorized
    case invalidResponse
    /// A refusal with a reason code, e.g. `pro_required`, `monthly_limit_reached`
    case rejected(code: String, message: String)

    var errorDescription: String? {
        switch self {
        case .rejected(_, let message):
            return message
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

    var refusalCode: String? {
        if case .rejected(let code, _) = self { return code }
        return nil
    }
}
