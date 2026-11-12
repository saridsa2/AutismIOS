import Foundation
import Security

struct LabSession: Codable {
    struct User: Codable { let id: String; let email: String }
    let accessToken: String
    let refreshToken: String
    let expiresAt: Double
    let user: User
}
enum LabKeychain {
    static func read() -> LabSession? {
        let query: [String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"app.littlecompany.voicelab",kSecAttrAccount as String:"session",kSecReturnData as String:true]
        var value: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary,&value) == errSecSuccess, let data = value as? Data else { return nil }
        return try? JSONDecoder().decode(LabSession.self,from:data)
    }
    static func save(_ session: LabSession?) throws {
        let query: [String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"app.littlecompany.voicelab",kSecAttrAccount as String:"session"]
        guard let session else { let status = SecItemDelete(query as CFDictionary); guard status == errSecSuccess || status == errSecItemNotFound else { throw LabError(message:"Could not clear sign-in.") }; return }
        let data = try JSONEncoder().encode(session)
        let updated = SecItemUpdate(query as CFDictionary,[kSecValueData as String:data] as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw LabError(message:"Could not save sign-in securely.") }
        var entry = query; entry[kSecValueData as String] = data; entry[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(entry as CFDictionary,nil) == errSecSuccess else { throw LabError(message:"Could not save sign-in securely.") }
    }
}
actor LabAPI {
    static let endpoint = "https://srv1938927.hstgr.cloud/api"
    private var session: LabSession? = LabKeychain.read()
    func current() -> LabSession? { session }
    private func send(_ path: String, body: Data?, method: String = "POST", token: String? = nil) async throws -> Data {
        var request = URLRequest(url: URL(string: Self.endpoint + path)!)
        request.httpMethod = method; request.httpBody = body; request.timeoutInterval = 45
        if body != nil { request.setValue("application/json",forHTTPHeaderField:"Content-Type") }
        if let token { request.setValue("Bearer \(token)",forHTTPHeaderField:"Authorization") }
        let (data,response) = try await URLSession.shared.data(for:request)
        guard let http = response as? HTTPURLResponse else { throw LabError(message:"No server response.") }
        guard (200..<300).contains(http.statusCode) else {
            let payload = (try? JSONSerialization.jsonObject(with:data)) as? [String:Any]
            throw LabError(message:payload?["error"] as? String ?? "Server request failed (\(http.statusCode)).")
        }
        return data
    }
    func login(email: String, password: String) async throws -> LabSession {
        let data = try await send("/auth/sign-in",body:JSONSerialization.data(withJSONObject:["email":email,"password":password]))
        let next = try JSONDecoder().decode(LabSession.self,from:data)
        try LabKeychain.save(next); session = next; return next
    }
    func signOut() throws { try LabKeychain.save(nil); session = nil }
    private func token() async throws -> String {
        guard let saved = session else { throw LabError(message:"Sign in before uploading.") }
        if saved.expiresAt > Date().timeIntervalSince1970 + 90 { return saved.accessToken }
        let data = try await send("/auth/refresh",body:JSONSerialization.data(withJSONObject:["refreshToken":saved.refreshToken]))
        let renewed = try JSONDecoder().decode(LabSession.self,from:data)
        try LabKeychain.save(renewed); session = renewed; return renewed.accessToken
    }
    func upload(_ sample: LabSample, wav: Data) async throws {
        let auth = try await token()
        let body: [String:Any] = ["id":sample.id.uuidString,"profileId":sample.profileID.uuidString,"label":sample.label,"kind":sample.kind,"modelID":SpeakerEngine.modelID,"embedding":sample.embedding,"wavBase64":wav.base64EncodedString(),"durationMs":sample.durationMs,"inferenceMs":sample.inferenceMs,"recordedAt":sample.createdAt.timeIntervalSince1970,"consentVersion":"voice-lab-v1","retentionDays":30]
        _ = try await send("/voice-lab/samples",body:JSONSerialization.data(withJSONObject:body),token:auth)
    }
    func delete(_ id: UUID) async throws { _ = try await send("/voice-lab/samples/\(id.uuidString)",body:nil,method:"DELETE",token:token()) }
}
