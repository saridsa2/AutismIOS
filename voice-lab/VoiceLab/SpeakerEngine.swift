import Foundation
import CoreML
import AVFoundation

struct LabError: LocalizedError { let message: String; var errorDescription: String? { message } }
struct VoiceProfile: Codable, Identifiable {
    let id: UUID
    var name: String
    var embeddings: [[Float]]
    var ready: Bool { embeddings.count >= 3 }
    var centroid: [Float] { (try? SpeakerMath.mean(embeddings)) ?? [] }
}
enum SpeakerMath {
    static func normalized(_ vector: [Float]) throws -> [Float] {
        guard !vector.isEmpty, vector.allSatisfy(\.isFinite) else { throw LabError(message: "Invalid speaker embedding.") }
        let norm = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        guard norm.isFinite, norm > 0.000001 else { throw LabError(message: "No usable speaker embedding.") }
        return vector.map { $0 / norm }
    }
    static func cosine(_ lhs: [Float], _ rhs: [Float]) -> Float {
        guard lhs.count == rhs.count, let a = try? normalized(lhs), let b = try? normalized(rhs) else { return -1 }
        return max(-1, min(1, zip(a,b).reduce(0) { $0 + $1.0 * $1.1 }))
    }
    static func mean(_ vectors: [[Float]]) throws -> [Float] {
        guard let first = vectors.first, vectors.allSatisfy({ $0.count == first.count }) else { throw LabError(message: "Incompatible speaker profiles.") }
        var sum = [Float](repeating: 0, count: first.count)
        for vector in vectors { let v = try normalized(vector); for i in v.indices { sum[i] += v[i] } }
        return try normalized(sum)
    }
    static func match(_ embedding: [Float], profiles: [VoiceProfile], threshold: Float, margin: Float = 0.08) -> (VoiceProfile?, Float) {
        let ranked = profiles.filter(\.ready).map { ($0, cosine(embedding,$0.centroid)) }.sorted { $0.1 > $1.1 }
        guard let best = ranked.first else { return (nil, 0) }
        guard best.1 >= threshold, ranked.count < 2 || best.1 - ranked[1].1 >= margin else { return (nil,best.1) }
        return (best.0,best.1)
    }
}
struct SampleQuality: Codable {
    let activeSeconds: Double
    let rmsDB: Double
    let clippedFraction: Double
    static func evaluate(_ samples: [Float]) throws -> SampleQuality {
        guard samples.count >= 48_000, samples.allSatisfy(\.isFinite) else { throw LabError(message: "Record at least three seconds of clear speech.") }
        let rms = sqrt(samples.reduce(0.0) { $0 + Double($1 * $1) } / Double(samples.count))
        let clipped = Double(samples.filter { abs($0) >= 0.99 }.count) / Double(samples.count)
        let active = stride(from: 0, to: samples.count, by: 320).filter { offset in
            let chunk = samples[offset..<min(offset + 320, samples.count)]
            return sqrt(chunk.reduce(0.0) { $0 + Double($1 * $1) } / Double(chunk.count)) > 0.0056
        }.count
        let quality = SampleQuality(activeSeconds: Double(active) * 0.02, rmsDB: 20 * log10(max(rms,1e-9)), clippedFraction: clipped)
        guard quality.activeSeconds >= 3, quality.rmsDB > -40 else { throw LabError(message: "Too little clear audio. Move closer and speak for at least three seconds.") }
        guard clipped < 0.01 else { throw LabError(message: "The recording is distorted. Move a little farther from the microphone.") }
        return quality
    }
}
actor SpeakerEngine {
    static let modelID = "community1-wespeaker-df2625ac-v1"
    private var fbank: MLModel?
    private var embedding: MLModel?
    func prepare() throws {
        guard fbank == nil else { return }
        guard let root = Bundle.main.resourceURL?.appendingPathComponent("Models") else { throw LabError(message: "Model resources unavailable.") }
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndGPU
        let loadedFBank = try MLModel(contentsOf: root.appendingPathComponent("FBank.mlmodelc"), configuration: config)
        let loadedEmbedding = try MLModel(contentsOf: root.appendingPathComponent("Embedding.mlmodelc"), configuration: config)
        fbank = loadedFBank; embedding = loadedEmbedding
    }
    func extract(url: URL) throws -> ([Float], SampleQuality, Double) {
        try prepare()
        let start = ProcessInfo.processInfo.systemUptime
        let file = try AVAudioFile(forReading: url)
        guard file.processingFormat.sampleRate == 16000, file.processingFormat.channelCount == 1, file.length <= 176_000,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw LabError(message: "Expected a short 16 kHz mono recording.")
        }
        try file.read(into: buffer)
        guard let channel = buffer.floatChannelData?[0] else { throw LabError(message: "Could not decode the sample.") }
        let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        let quality = try SampleQuality.evaluate(samples)
        let audio = try MLMultiArray(shape: [1,1,160000], dataType: .float32)
        let ptr = audio.dataPointer.assumingMemoryBound(to: Float.self)
        for i in 0..<160000 { ptr[i] = i < samples.count ? samples[i] : 0 }
        let features = try fbank!.prediction(from: MLDictionaryFeatureProvider(dictionary: ["audio": audio]))
        guard let bank = features.featureValue(for: "fbank_features") else { throw LabError(message: "Audio features missing.") }
        let weights = try MLMultiArray(shape: [1,589], dataType: .float32)
        for i in 0..<589 {
            let lo = i * 160000 / 589, hi = min((i + 1) * 160000 / 589, samples.count)
            let energy: Float = lo < hi ? samples[lo..<hi].reduce(0) { $0 + $1 * $1 } / Float(hi-lo) : 0
            weights[i] = NSNumber(value: energy > 0.00003136 ? Float(1) : Float(0))
        }
        let output = try embedding!.prediction(from: MLDictionaryFeatureProvider(dictionary: ["fbank_features":bank,"weights":MLFeatureValue(multiArray:weights)]))
        guard let values = output.featureValue(for: "embedding")?.multiArrayValue, values.count == 256 else { throw LabError(message: "Unexpected embedding output.") }
        let vector = try SpeakerMath.normalized((0..<values.count).map { values[$0].floatValue })
        return (vector, quality, (ProcessInfo.processInfo.systemUptime-start)*1000)
    }
}
