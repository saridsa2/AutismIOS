import Foundation
import AVFoundation
import SwiftUI

struct LabSample: Codable, Identifiable {
    let id: UUID
    let profileID: UUID
    let label: String
    let kind: String
    let createdAt: Date
    let embedding: [Float]
    let durationMs: Double
    let inferenceMs: Double
    let quality: SampleQuality
    var uploadedOwner: String?
    var uploadMs: Double?
}
private struct LabArchive: Codable { var profiles: [VoiceProfile]; var samples: [LabSample] }
@MainActor final class LabStore: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var profiles: [VoiceProfile] = []
    @Published var samples: [LabSample] = []
    @Published var selectedProfile: UUID?
    @Published var profileName = ""
    @Published var recording = false
    @Published var processing = false
    @Published var busy = false
    @Published var elapsed: Double = 0
    @Published var level: Float = 0
    @Published var status = "Create a speaker profile to begin."
    @Published var modelReady = false
    @Published var account: LabSession?
    @Published var consent = false
    @Published var uploadConsent = false
    @Published var threshold: Double = 0.75
    private let engine = SpeakerEngine()
    private let api = LabAPI()
    private var recorder: AVAudioRecorder?
    private var ticker: Task<Void,Never>?
    private var recordingID: UUID?
    private var recordingProfile: UUID?
    private var recordingKind = "enrollment"
    private var interruption: NSObjectProtocol?
    let root: URL
    override init() {
        root = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("VoiceLab",isDirectory:true)
        super.init()
        do {
            try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true,attributes:[.protectionKey:FileProtectionType.complete])
            var protectedRoot = root
            var values = URLResourceValues(); values.isExcludedFromBackup = true; try protectedRoot.setResourceValues(values)
            let archiveURL = root.appendingPathComponent("library.json")
            if FileManager.default.fileExists(atPath:archiveURL.path) {
                let archive = try JSONDecoder().decode(LabArchive.self,from:Data(contentsOf:archiveURL))
                profiles = archive.profiles; samples = archive.samples; selectedProfile = profiles.first?.id
            }
        } catch { status = "Could not open the local library: \(error.localizedDescription)" }
        interruption = NotificationCenter.default.addObserver(forName:AVAudioSession.interruptionNotification,object:nil,queue:.main) { [weak self] _ in
            Task { @MainActor in self?.cancelRecording() }
        }
    }
    func prepare() async {
        account = await api.current()
        do { try await engine.prepare(); modelReady = true; status = "Ready. Record three samples per speaker." }
        catch { status = "Model could not load: \(error.localizedDescription)" }
    }
    private func persist() throws {
        try JSONEncoder().encode(LabArchive(profiles:profiles,samples:samples)).write(to:root.appendingPathComponent("library.json"),options:[.atomic,.completeFileProtection])
    }
    func addProfile() {
        let name = profileName.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 80 else { status = "Use a name of 1–80 characters."; return }
        let profile = VoiceProfile(id:UUID(),name:name,embeddings:[])
        profiles.append(profile); selectedProfile = profile.id; profileName = ""
        do { try persist(); status = "Record three different ten-second samples for \(name)." }
        catch { profiles.removeAll { $0.id == profile.id }; status = error.localizedDescription }
    }
    func startRecording(kind: String) async {
        guard consent, modelReady, !recording, !processing, !busy, let id = selectedProfile, profiles.contains(where:{$0.id == id}) else { return }
        busy = true; defer { busy = false }
        guard await AVAudioApplication.requestRecordPermission() else { status = "Allow microphone access in Settings."; return }
        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.playAndRecord,mode:.default,options:[.defaultToSpeaker])
            try audio.setActive(true)
            let sampleID = UUID(); let url = fileURL(sampleID)
            let device = try AVAudioRecorder(url:url,settings:[AVFormatIDKey:kAudioFormatLinearPCM,AVSampleRateKey:16000,AVNumberOfChannelsKey:1,AVLinearPCMBitDepthKey:16,AVLinearPCMIsFloatKey:false,AVLinearPCMIsBigEndianKey:false])
            device.delegate = self; device.isMeteringEnabled = true
            guard device.prepareToRecord(), device.record(forDuration:10) else { throw LabError(message:"Could not start recording.") }
            try FileManager.default.setAttributes([.protectionKey:FileProtectionType.complete],ofItemAtPath:url.path)
            recorder = device; recordingID = sampleID; recordingProfile = id; recordingKind = kind
            recording = true; elapsed = 0; status = "Recording — speak naturally for ten seconds."
            ticker = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for:.milliseconds(100))
                    guard let self, self.recording else { return }
                    self.recorder?.updateMeters(); self.elapsed = self.recorder?.currentTime ?? 0
                    self.level = max(0,min(1,((self.recorder?.averagePower(forChannel:0) ?? -60) + 60) / 60))
                }
            }
        } catch { cancelRecording(); status = error.localizedDescription }
    }
    func cancelRecording() {
        guard recording || recordingID != nil else { return }
        recorder?.delegate = nil; recorder?.stop(); recorder = nil; ticker?.cancel()
        if let id = recordingID { try? FileManager.default.removeItem(at:fileURL(id)) }
        recordingID = nil; recordingProfile = nil; recording = false; level = 0
        try? AVAudioSession.sharedInstance().setActive(false)
        status = "Recording cancelled."
    }
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in await self.finishRecording(success:flag) }
    }
    private func finishRecording(success: Bool) async {
        guard let id = recordingID, let profileID = recordingProfile else { return }
        let duration = recorder?.currentTime ?? 10
        let kind = recordingKind
        ticker?.cancel(); recorder = nil; recording = false; recordingID = nil; recordingProfile = nil; level = 0
        try? AVAudioSession.sharedInstance().setActive(false)
        guard success else { try? FileManager.default.removeItem(at:fileURL(id)); status = "Recording interrupted. Please try again."; return }
        processing = true; defer { processing = false }
        status = "Computing speaker fingerprint on this device…"
        do {
            let (vector,quality,ms) = try await engine.extract(url:fileURL(id))
            guard let index = profiles.firstIndex(where:{$0.id == profileID}) else { throw LabError(message:"Speaker profile no longer exists.") }
            if kind == "enrollment" {
                if !profiles[index].embeddings.isEmpty, SpeakerMath.cosine(vector,profiles[index].centroid) < 0.5 { throw LabError(message:"This sample differs from the profile. Check the selected speaker and try again in a quiet room.") }
                profiles[index].embeddings.append(vector)
                status = profiles[index].ready ? "\(profiles[index].name) enrolled. Test with a new recording." : "Saved sample \(profiles[index].embeddings.count) of 3."
            } else {
                let (match,score) = SpeakerMath.match(vector,profiles:profiles,threshold:Float(threshold))
                status = "\(match?.name ?? "Unknown speaker") · similarity \(String(format:"%.2f",score)) · \(Int(ms)) ms processing"
            }
            samples.append(LabSample(id:id,profileID:profileID,label:profiles[index].name,kind:kind,createdAt:Date(),embedding:vector,durationMs:(duration > 0 ? duration : 10)*1000,inferenceMs:ms,quality:quality))
            do { try persist() }
            catch { samples.removeAll{$0.id == id}; if kind == "enrollment" { profiles[index].embeddings.removeLast() }; throw error }
        } catch { try? FileManager.default.removeItem(at:fileURL(id)); status = error.localizedDescription }
    }
    func fileURL(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString + ".wav") }
    func login(email: String,password: String) async {
        busy = true; defer { busy = false }
        do { account = try await api.login(email:email.trimmingCharacters(in:.whitespacesAndNewlines),password:password); status = "Signed in. Samples remain local until you upload." }
        catch { status = error.localizedDescription }
    }
    func signOut() async { do { try await api.signOut(); account = nil; uploadConsent = false } catch { status = error.localizedDescription } }
    func uploadPending() async {
        guard uploadConsent, let owner = account?.user.id else { return }
        busy = true; defer { busy = false }
        for sample in samples where sample.uploadedOwner == nil {
            do {
                let start = ProcessInfo.processInfo.systemUptime
                try await api.upload(sample,wav:Data(contentsOf:fileURL(sample.id)))
                guard let index = samples.firstIndex(where:{$0.id == sample.id}) else { continue }
                samples[index].uploadedOwner = owner; samples[index].uploadMs = (ProcessInfo.processInfo.systemUptime-start)*1000
                try persist()
            } catch { status = "Upload paused; local samples kept. \(error.localizedDescription)"; return }
        }
        status = "Upload complete. Remote samples expire after 30 days."
    }
    func deleteSample(_ sample: LabSample) async {
        busy = true; defer { busy = false }
        do {
            if let owner = sample.uploadedOwner {
                guard account?.user.id == owner else { throw LabError(message:"Sign in to the account that uploaded this sample to delete its remote copy.") }
                try await api.delete(sample.id)
            }
            var nextSamples = samples; nextSamples.removeAll { $0.id == sample.id }
            var nextProfiles = profiles
            if let index = nextProfiles.firstIndex(where:{$0.id == sample.profileID}), sample.kind == "enrollment" {
                nextProfiles[index].embeddings = nextSamples.filter{$0.profileID == sample.profileID && $0.kind == "enrollment"}.map(\.embedding)
            }
            try JSONEncoder().encode(LabArchive(profiles:nextProfiles,samples:nextSamples)).write(to:root.appendingPathComponent("library.json"),options:[.atomic,.completeFileProtection])
            profiles = nextProfiles; samples = nextSamples
            try FileManager.default.removeItem(at:fileURL(sample.id)); status = "Sample deleted."
        } catch { status = error.localizedDescription }
    }
}
