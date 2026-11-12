import Foundation

struct AccountUser: Codable { let id: String; let email: String }
struct AccountSession: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Double
    let user: AccountUser
    static func restored() -> AccountSession? {
        try? JSONDecoder().decode(AccountSession.self, from: Data(Vault.get("accountSession").utf8))
    }
}
struct AccountDevice: Decodable, Identifiable {
    let installation_id: String
    let platform: String
    let last_seen_at: String
    var id: String { installation_id }
}
struct AccountInfo: Decodable {
    let email: String
    let createdAt: String
    let devices: [AccountDevice]
    let sessionCount: Int
}

// The app only knows our API. Supabase and provider credentials stay on the server.
enum AppService {
    static let endpoint = "https://srv1938927.hstgr.cloud/api"
    static let installationID: String = {
        if let saved = UserDefaults.standard.string(forKey: "installationID") { return saved }
        let value = UUID().uuidString
        UserDefaults.standard.set(value, forKey: "installationID")
        return value
    }()
}
