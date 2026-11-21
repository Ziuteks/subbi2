import Foundation

/// Błąd zwrócony przez serwer (lub problem z połączeniem) – `message` nadaje się do pokazania użytkownikowi.
struct APIError: LocalizedError {
    /// Kod HTTP; 0 = brak połączenia / nieprawidłowy adres.
    let status: Int
    let message: String

    var errorDescription: String? { message }
    var isUnauthorized: Bool { status == 401 }
}

struct AuthUser: Codable, Equatable {
    let id: String
    var email: String
    var name: String
}

struct AuthSession: Decodable {
    let token: String
    let user: AuthUser
}

/// Klient REST dla subbi-backend (zob. README w repozytorium subbi-backend).
struct APIClient {
    var baseURL: String
    var token: String?

    // MARK: - Konta

    func register(name: String, email: String, password: String) async throws -> AuthSession {
        try await send("POST", "/auth/register", body: ["name": name, "email": email, "password": password])
    }

    func login(email: String, password: String) async throws -> AuthSession {
        try await send("POST", "/auth/login", body: ["email": email, "password": password])
    }

    func changePassword(current: String, new: String) async throws -> AuthSession {
        try await send("POST", "/auth/change-password", body: ["currentPassword": current, "newPassword": new])
    }

    func me() async throws -> AuthUser {
        try await send("GET", "/me")
    }

    func updateProfile(name: String, email: String) async throws -> AuthUser {
        try await send("PATCH", "/me", body: ["name": name, "email": email])
    }

    // MARK: - Subskrypcje

    func fetchSubscriptions() async throws -> [Subscription] {
        try await send("GET", "/subscriptions")
    }

    @discardableResult
    func saveSubscriptions(_ subs: [Subscription]) async throws -> [Subscription] {
        try await send("PUT", "/subscriptions", body: subs)
    }

    // MARK: - Transport

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = try? Date(text, strategy: .iso8601) { return date }
            if let date = try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Nieprawidłowa data: \(text)"))
        }
        return d
    }()

    private struct ErrorBody: Decodable { let error: String }
    private struct Empty: Encodable {}

    private func send<Response: Decodable>(_ method: String, _ path: String,
                                           body: (any Encodable)? = nil) async throws -> Response {
        let trimmed = baseURL.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: trimmed + path), url.scheme?.hasPrefix("http") == true, url.host() != nil else {
            throw APIError(status: 0, message: "Nieprawidłowy adres serwera.")
        }

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try Self.encoder.encode(body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw APIError(status: 0, message: "Nie można połączyć się z serwerem. Sprawdź adres i połączenie z internetem.")
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = (try? Self.decoder.decode(ErrorBody.self, from: data))?.error
                ?? "Błąd serwera (\(status))."
            throw APIError(status: status, message: message)
        }

        do {
            return try Self.decoder.decode(Response.self, from: data)
        } catch {
            throw APIError(status: status, message: "Nieoczekiwana odpowiedź serwera.")
        }
    }
}
