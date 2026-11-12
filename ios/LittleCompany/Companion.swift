import SwiftUI
import LiveKit
import MusicKit
import AVFoundation
import Security

struct SessionCredentials: Decodable { let url: String; let token: String }
struct ServiceFailure: Decodable { let code: String?; let error: String? }
struct MusicCommand: Decodable { let action: String; let query: String? }
struct CareProfile: Codable { var childName: String; var today: String; var context: String }

enum Vault {
    static func get(_ key: String) -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "app.littlecompany.companion", kSecAttrAccount as String: key, kSecReturnData as String: true]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func set(_ key: String, _ value: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "app.littlecompany.companion", kSecAttrAccount as String: key]
        let data = Data(value.utf8)
        let updated = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else {
            throw AppError.message("Could not save access settings securely (Keychain \(updated)).")
        }
        var entry = query
        entry[kSecValueData as String] = data
        entry[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let added = SecItemAdd(entry as CFDictionary, nil)
        guard added == errSecSuccess else {
            throw AppError.message("Could not save access settings securely (Keychain \(added)).")
        }
    }
}

@MainActor
final class Companion: ObservableObject {
    @Published var status = "A little hello awaits"
    @Published var detail = "Ask a grown-up to set up your companion."
    @Published var connected = false
    @Published var paused = false
    @Published var connecting = false
    @Published var speaking = false
    @Published var song = ""
    @Published var musicPlaying = false
    @Published var musicAuthorized = false
    @Published var settingsMessage = ""
    @Published var voiceUnavailable = false
    @Published var account = AccountSession.restored()
    @Published var accountInfo: AccountInfo?
    @Published var authBusy = false
    @Published var authMessage = ""
    @Published var childName = ""
    private var refreshTask: Task<AccountSession, Error>?
    private var accountGeneration = 0
    @Published var today = ""
    @Published var context = ""
    @Published var reduceMotion = UserDefaults.standard.bool(forKey: "reduceMotion")
    @Published var animateSpeech = UserDefaults.standard.object(forKey: "animateSpeech") as? Bool ?? true
    var connectionLabel: String {
        if !signedIn { return "SIGN IN NEEDED" }
        if voiceUnavailable { return "VOICE UNAVAILABLE" }
        if connecting { return "CONNECTING" }
        if connected { return paused ? "PAUSED" : "CONNECTED" }
        if status == "Finding your companion" { return "WAITING FOR AGENT" }
        if status == "Taking a little break" { return "PAUSED" }
        if status == "Microphone is off" { return "MICROPHONE OFF" }
        return "OFFLINE"
    }
    let room = Room()
    private var monitor: Task<Void, Never>?
    private var speechMonitor: Task<Void, Never>?
    private var retry: Task<Void, Never>?
    @Published private(set) var wantsConnection = false
    private var failureCount = 0
    private var musicRequestRunning = false
    private var connectionGeneration = 0
    private var missingAgentSeconds = 0

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["LITTLE_COMPANY_TLS_DIAGNOSTICS"] == "1" {
            Task { [weak self] in
                do {
                    _ = try await self?.rawRequest("/health", method: "GET")
                    print("[NetworkDiagnostics] health request succeeded")
                } catch {
                    print("[NetworkDiagnostics] health request failed")
                    let failure = error as NSError
                    if let value = failure.userInfo[NSURLErrorFailingURLPeerTrustErrorKey],
                       CFGetTypeID(value as CFTypeRef) == SecTrustGetTypeID() {
                        let trust = value as! SecTrust
                        var trustError: CFError?
                        let trusted = SecTrustEvaluateWithError(trust, &trustError)
                        print("[NetworkDiagnostics] trusted=\(trusted) error=\(String(describing: trustError))")
                    }
                    print("[NetworkDiagnostics] health error=\(failure)")
                }
            }
        }
        #endif
        #if DEBUG && targetEnvironment(simulator)
        // Local development provisioning uses a normal, per-device account session.
        if let json = ProcessInfo.processInfo.environment["LITTLE_COMPANY_ACCOUNT_SESSION"],
           let session = try? JSONDecoder().decode(AccountSession.self, from: Data(json.utf8)) {
            try? persistAccount(session)
        }
        #endif
        // Remove the prototype's shared access credentials after migrating to accounts.
        try? Vault.set("deviceToken", "")
        try? Vault.set("adminToken", "")
        UserDefaults.standard.removeObject(forKey: "endpoint")
        // Own the session so MusicKit and the LiveKit microphone can coexist.
        AudioManager.shared.audioSession.isAutomaticConfigurationEnabled = false
        speechMonitor = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self else { return }
                let active = self.room.connectionState == .connected && !self.paused &&
                    self.room.remoteParticipants.values.contains {
                        guard $0.kind == .agent else { return false }
                        // AgentSession publishes its speech state independently of
                        // server audio-level updates, which may be unavailable.
                        if let state = $0.attributes["lk.agent.state"] {
                            return state == "speaking"
                        }
                        return $0.isSpeaking
                    }
                if self.speaking != active { self.speaking = active }
            }
        }
        monitor = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                let online = self.room.connectionState == .connected
                let agentPresent = self.room.remoteParticipants.values.contains { $0.kind == .agent }
                self.connected = online && agentPresent
                self.musicPlaying = ApplicationMusicPlayer.shared.state.playbackStatus == .playing
                if online {
                    self.missingAgentSeconds = agentPresent ? 0 : self.missingAgentSeconds + 1
                    if self.missingAgentSeconds >= 45 && !self.connecting {
                        self.missingAgentSeconds = 0
                        await self.room.disconnect()
                        continue
                    }
                    self.failureCount = 0
                    self.status = self.paused ? "Taking a little break" : (agentPresent ? (self.speaking ? "A little something for you" : "I'm here") : "Finding your companion")
                    self.detail = self.paused ? "Your microphone is paused." : (agentPresent ? "Take your time. There's no hurry." : "Waiting for the voice agent to join.")
                } else if self.wantsConnection && !self.connecting && self.retry == nil {
                    self.status = "Finding our way back"
                    self.detail = "Reconnecting to your companion."
                    self.failureCount += 1
                    let delay = min(30, 2 * self.failureCount)
                    self.retry = Task { [weak self] in
                        try? await Task.sleep(for: .seconds(delay))
                        guard !Task.isCancelled, let self else { return }
                        self.retry = nil
                        await self.connect()
                    }
                }
            }
        }
    }
    @discardableResult
    func save() -> Bool {
        UserDefaults.standard.set(reduceMotion, forKey: "reduceMotion")
        UserDefaults.standard.set(animateSpeech, forKey: "animateSpeech")
        return true
    }
    var signedIn: Bool { account != nil }
    var greetingName: String { childName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var deviceBody: Data {
        try! JSONSerialization.data(withJSONObject: ["installationId": AppService.installationID, "platform": UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"])
    }
    func rawRequest(_ path: String, method: String = "POST", token: String? = nil, body: Data? = nil) async throws -> Data {
        var req = URLRequest(url: URL(string: AppService.endpoint + path)!)
        req.httpMethod = method; req.timeoutInterval = 25
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { req.httpBody = body; req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            #if DEBUG
            var current: NSError? = error as NSError
            for depth in 0..<6 {
                guard let failure = current else { break }
                print("[NetworkDiagnostics] depth=\(depth) domain=\(failure.domain) code=\(failure.code)")
                for key in ["_kCFStreamErrorDomainKey", "_kCFStreamErrorCodeKey"] {
                    if let value = failure.userInfo[key] as? NSNumber {
                        print("[NetworkDiagnostics] \(key)=\(value)")
                    }
                }
                current = failure.userInfo[NSUnderlyingErrorKey] as? NSError
            }
            #endif
            throw error
        }
        guard let http = response as? HTTPURLResponse else { throw AppError.message("Could not reach Little Company.") }
        let failure = try? JSONDecoder().decode(ServiceFailure.self, from: data)
        if failure?.code == "GEMINI_QUOTA_EXCEEDED" { throw AppError.voiceQuota }
        if http.statusCode == 401 { throw AppError.signInRequired }
        guard (200..<300).contains(http.statusCode) else { throw AppError.message(failure?.error ?? "Could not reach Little Company. Please try again.") }
        return data
    }
    private func persistAccount(_ session: AccountSession) throws {
        try Vault.set("accountSession", String(decoding: JSONEncoder().encode(session), as: UTF8.self))
        account = session
    }
    private func refreshAccount() async throws {
        guard let current = account else { throw AppError.signInRequired }
        let epoch = accountGeneration
        let task: Task<AccountSession, Error>
        if let running = refreshTask { task = running }
        else {
            task = Task {
                let body = try JSONSerialization.data(withJSONObject: ["refreshToken": current.refreshToken])
                let data = try await self.rawRequest("/auth/refresh", body: body)
                return try JSONDecoder().decode(AccountSession.self, from: data)
            }
            refreshTask = task
        }
        defer { refreshTask = nil }
        do {
            let renewed = try await task.value
            guard epoch == accountGeneration else { throw AppError.signInRequired }
            try persistAccount(renewed)
        } catch AppError.signInRequired {
            if epoch == accountGeneration { await clearAccount() }
            throw AppError.signInRequired
        }
    }
    func request(_ path: String, method: String = "GET", body: Data? = nil) async throws -> Data {
        guard let current = account else { throw AppError.signInRequired }
        if current.expiresAt < Date().timeIntervalSince1970 + 60 { try await refreshAccount() }
        do { return try await rawRequest(path, method: method, token: account?.accessToken, body: body) }
        catch AppError.signInRequired {
            try await refreshAccount()
            do { return try await rawRequest(path, method: method, token: account?.accessToken, body: body) }
            catch AppError.signInRequired { await clearAccount(); throw AppError.signInRequired }
        }
    }
    @discardableResult
    func authenticate(_ action: String, email: String, password: String = "", code: String = "") async -> Bool {
        guard !authBusy else { return false }
        authBusy = true; authMessage = ""; defer { authBusy = false }
        do {
            let body = try JSONSerialization.data(withJSONObject: ["email": email.trimmingCharacters(in: .whitespacesAndNewlines), "password": password, "code": code])
            let data = try await rawRequest("/auth/\(action)", body: body)
            if ["sign-in", "verify", "reset"].contains(action) {
                accountGeneration += 1
                try persistAccount(JSONDecoder().decode(AccountSession.self, from: data))
                await prepareAccount()
                await connect()
            } else {
                let message = (try? JSONSerialization.jsonObject(with: data)) as? [String: String]
                authMessage = message?["message"] ?? "Check your email."
            }
            return true
        } catch AppError.signInRequired {
            authMessage = "Could not sign in. Check your email and password, and verify your email first."
        } catch { authMessage = error.localizedDescription }
        return false
    }
    func prepareAccount() async {
        do {
            _ = try await request("/device", method: "PUT", body: deviceBody)
            let p = try JSONDecoder().decode(CareProfile.self, from: await request("/profile"))
            childName = p.childName; today = p.today; context = p.context
            await loadAccount()
        } catch { settingsMessage = error.localizedDescription }
    }
    func loadAccount() async {
        do { accountInfo = try JSONDecoder().decode(AccountInfo.self, from: await request("/account")) }
        catch { settingsMessage = error.localizedDescription }
    }
    func signOut() async {
        guard !authBusy else { return }
        authBusy = true; defer { authBusy = false }
        await stop()
        do {
            _ = try await request("/auth/sign-out", method: "POST")
            await clearAccount()
        } catch AppError.signInRequired { await clearAccount() }
        catch { settingsMessage = "Could not finish signing out. Check your connection and try again." }
    }
    private func clearAccount() async {
        accountGeneration += 1
        refreshTask?.cancel(); refreshTask = nil
        await stop()
        do { try Vault.set("accountSession", "") }
        catch { settingsMessage = error.localizedDescription; return }
        account = nil; accountInfo = nil; childName = ""; today = ""; context = ""
        voiceUnavailable = false; paused = false; song = ""
        settingsMessage = ""; authMessage = ""
        status = "A little hello awaits"; detail = "A grown-up can sign in to get started."
    }
    func start() async {
        guard signedIn else { return }
        await prepareAccount()
        await connect()
    }
    func connect() async {
        guard !connecting else { return }
        guard signedIn else { return }
        voiceUnavailable = false
        retry?.cancel(); retry = nil
        connectionGeneration += 1
        let generation = connectionGeneration
        connecting = true; defer { connecting = false }
        wantsConnection = true; status = "Getting ready"; detail = "Connecting your voice companion."
        let granted = await AVAudioApplication.requestRecordPermission()
        guard generation == connectionGeneration else { return }
        guard granted else { wantsConnection = false; status = "Microphone is off"; detail = "A grown-up can enable it in iPad Settings."; return }
        do {
            await room.disconnect()
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])
            try audio.setActive(true)
            let creds = try JSONDecoder().decode(SessionCredentials.self, from: await request("/session", method: "POST", body: deviceBody))
            guard generation == connectionGeneration else { return }
            await room.unregisterRpcMethod("music")
            try await room.registerRpcMethod("music") { [weak self] invocation in
                guard let self else { return "{\"ok\":false}" }
                return await self.handleMusic(invocation.payload, caller: invocation.callerIdentity)
            }
            try await room.connect(url: creds.url, token: creds.token)
            guard generation == connectionGeneration else { await room.disconnect(); return }
            try await room.localParticipant.setMicrophone(enabled: !paused)
        } catch AppError.signInRequired {
            wantsConnection = false
            settingsMessage = "Please sign in again."
            await room.disconnect()
        } catch AppError.voiceQuota {
            wantsConnection = false
            voiceUnavailable = true
            status = "A little quiet for now"
            detail = "A grown-up needs to check the voice service."
            settingsMessage = AppError.voiceQuota.localizedDescription
            await room.disconnect()
        } catch {
            status = "We couldn't connect yet"
            detail = error.localizedDescription
            settingsMessage = error.localizedDescription
        }
    }
    func stop() async {
        connectionGeneration += 1
        wantsConnection = false; retry?.cancel(); retry = nil
        await room.disconnect(); connected = false
        ApplicationMusicPlayer.shared.pause()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        status = "Taking a little break"; detail = "Your microphone is off."
    }
    func togglePause() async {
        let next = !paused
        do { try await room.localParticipant.setMicrophone(enabled: !next); paused = next }
        catch { settingsMessage = "Could not change microphone state." }
    }
    func authorizeMusic() async {
        musicAuthorized = await MusicAuthorization.request() == .authorized
        settingsMessage = musicAuthorized ? "Apple Music connected." : "Apple Music permission was not granted."
    }
    func loadProfile() async {
        do { let p = try JSONDecoder().decode(CareProfile.self, from: await request("/profile")); childName = p.childName; today = p.today; context = p.context; settingsMessage = "Context loaded." }
        catch { settingsMessage = error.localizedDescription }
    }
    func saveProfile() async {
        do { _ = try await request("/profile", method: "PUT", body: JSONEncoder().encode(CareProfile(childName: childName, today: today, context: context))); settingsMessage = "Saved. Reconnect to use the updated context." }
        catch { settingsMessage = error.localizedDescription }
    }
    func handleMusic(_ payload: String, caller: Participant.Identity) async -> String {
        func result(_ ok: Bool, _ message: String) -> String {
            let data = try! JSONSerialization.data(withJSONObject: ["ok": ok, "message": message])
            return String(decoding: data, as: UTF8.self)
        }
        guard room.remoteParticipants[caller]?.kind == .agent else { return result(false, "Unauthorized caller") }
        guard !musicRequestRunning else { return result(false, "Another music request is still running") }
        musicRequestRunning = true; defer { musicRequestRunning = false }
        do {
            let command = try JSONDecoder().decode(MusicCommand.self, from: Data(payload.utf8))
            let player = ApplicationMusicPlayer.shared
            if command.action == "pause" { player.pause(); return result(true, "Music paused") }
            guard MusicAuthorization.currentStatus == .authorized else { return result(false, "A caregiver needs to connect Apple Music in settings") }
            guard try await MusicSubscription.current.canPlayCatalogContent else { return result(false, "An Apple Music subscription is required") }
            switch command.action {
            case "play":
                var search = MusicCatalogSearchRequest(term: String((command.query ?? "ABBA").prefix(150)), types: [Song.self]); search.limit = 12
                let response = try await search.response()
                guard let first = response.songs.first else { return result(false, "No matching song found") }
                player.queue = ApplicationMusicPlayer.Queue(for: response.songs)
                try await player.play(); song = "\(first.title) · \(first.artistName)"
            case "resume": try await player.play()
            case "next": try await player.skipToNextEntry(); song = player.queue.currentEntry?.title ?? "Your music"
            case "repeat": player.playbackTime = 0; try await player.play()
            default: return result(false, "Unsupported music command")
            }
            return result(true, "Music command completed")
        } catch { return result(false, "Music playback failed. Ask a grown-up to check Apple Music.") }
    }
}
enum AppError: LocalizedError {
    case message(String)
    case voiceQuota
    case signInRequired
    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        case .voiceQuota: return "Voice is temporarily unavailable. Please try Reconnect later. Your family settings are saved."
        case .signInRequired: return "Please sign in again."
        }
    }
}
