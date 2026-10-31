import Foundation

enum MonitorError: LocalizedError {
    case notConnected, http(Int), loginExpired, badResponse
    var errorDescription: String? {
        switch self {
        case .notConnected: return "Conecte sua conta para consultar a cota."
        case .http(401): return "A sessão expirou. Reconecte sua conta."
        case .http(403): return "A OpenAI não autorizou esta operação. Confira as permissões da conta."
        case .http(429): return "Muitas consultas. Aguarde alguns minutos."
        case .http(let code): return "O serviço respondeu com erro \(code). Tente novamente mais tarde."
        case .loginExpired: return "O código de conexão expirou. Gere um novo código."
        case .badResponse: return "O serviço retornou uma resposta inesperada."
        }
    }
}

struct DeviceAuthorization: Sendable {
    let id: String
    let code: String
    let interval: TimeInterval
    let expiresAt: Date
    static let verificationURL = URL(string: "https://auth.openai.com/codex/device")!
}

private final class RejectRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// Personal integration prototype using the public Codex client's device flow.
/// The usage endpoint is internal, not a supported third-party API contract.
struct CodexClient: Sendable {
    static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann" // Public identifier, not a secret.
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        session = URLSession(configuration: configuration, delegate: RejectRedirects(), delegateQueue: nil)
    }

    func requestDeviceAuthorization() async throws -> DeviceAuthorization {
        let data = try await jsonPost("https://auth.openai.com/api/accounts/deviceauth/usercode",
                                      body: ["client_id": Self.clientID])
        struct Response: Decodable {
            let device_auth_id: String
            let user_code: String?
            let usercode: String?
            let interval: FlexibleInterval?
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard let code = response.user_code ?? response.usercode, !code.isEmpty else { throw MonitorError.badResponse }
        return DeviceAuthorization(id: response.device_auth_id, code: code,
            interval: max(5, response.interval?.value ?? 5), expiresAt: Date().addingTimeInterval(900))
    }

    func waitForAuthorization(_ authorization: DeviceAuthorization) async throws -> Credentials {
        while Date() < authorization.expiresAt {
            try Task.checkCancellation()
            do {
                let data = try await jsonPost("https://auth.openai.com/api/accounts/deviceauth/token",
                    body: ["device_auth_id": authorization.id, "user_code": authorization.code])
                struct Response: Decodable { let authorization_code: String; let code_verifier: String }
                let response = try JSONDecoder().decode(Response.self, from: data)
                try Task.checkCancellation()
                return try await tokenRequest([
                    "grant_type": "authorization_code", "client_id": Self.clientID,
                    "code": response.authorization_code, "code_verifier": response.code_verifier,
                    "redirect_uri": "https://auth.openai.com/deviceauth/callback"
                ], previous: nil)
            } catch MonitorError.http(let code) where code == 403 || code == 404 {
                try await Task.sleep(for: .seconds(authorization.interval))
            }
        }
        throw MonitorError.loginExpired
    }

    func refresh(_ credentials: Credentials) async throws -> Credentials {
        try await tokenRequest(["grant_type": "refresh_token", "client_id": Self.clientID,
                                "refresh_token": credentials.refreshToken], previous: credentials)
    }

    func quota(using credentials: Credentials) async throws -> QuotaSnapshot {
        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        if let accountID = credentials.accountID {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        let data = try await send(request)
        return try QuotaDecoder.decode(data)
    }

    private func tokenRequest(_ fields: [String: String], previous: Credentials?) async throws -> Credentials {
        var request = URLRequest(url: URL(string: "https://auth.openai.com/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        request.httpBody = fields.sorted { $0.key < $1.key }.map {
            "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")"
        }.joined(separator: "&").data(using: .utf8)
        struct Tokens: Decodable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Double?
        }
        let tokens = try JSONDecoder().decode(Tokens.self, from: try await send(request))
        guard !tokens.access_token.isEmpty,
              let refresh = tokens.refresh_token ?? previous?.refreshToken, !refresh.isEmpty else {
            throw MonitorError.badResponse
        }
        let claims = Self.claims(tokens.access_token)
        let auth = claims?["https://api.openai.com/auth"] as? [String: Any]
        return Credentials(accessToken: tokens.access_token, refreshToken: refresh,
            expiresAt: (claims?["exp"] as? Double).map { Date(timeIntervalSince1970: $0) }
                ?? Date().addingTimeInterval(tokens.expires_in ?? 3600),
            accountID: auth?["chatgpt_account_id"] as? String ?? previous?.accountID)
    }

    private static func claims(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count > 1 else { return nil }
        var value = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        value += String(repeating: "=", count: (4 - value.count % 4) % 4)
        guard let data = Data(base64Encoded: value) else { return nil }
        // Decode metadata only; the service validates the token's authenticity.
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private func jsonPost(_ url: String, body: [String: String]) async throws -> Data {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await send(request)
    }

    private func send(_ original: URLRequest) async throws -> Data {
        var request = original
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("CodexMonitor-iOS/0.1", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw MonitorError.badResponse }
        guard (200..<300).contains(response.statusCode) else { throw MonitorError.http(response.statusCode) }
        guard data.count <= 2_000_000 else { throw MonitorError.badResponse }
        return data
    }

    private struct FlexibleInterval: Decodable {
        let value: Double
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let number = try? container.decode(Double.self) { value = number }
            else if let number = Double(try container.decode(String.self)), number.isFinite { value = number }
            else { throw MonitorError.badResponse }
        }
    }
}
