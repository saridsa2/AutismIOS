import XCTest
@testable import VoiceLab
final class SpeakerTests: XCTestCase {
    func testUnknownWhenProfilesAreIncompleteOrAmbiguous() throws {
        let vector: [Float] = [1,0,0]
        let pending = VoiceProfile(id:UUID(),name:"Pending",embeddings:[vector])
        XCTAssertNil(SpeakerMath.match(vector,profiles:[pending],threshold:0.75).0)
        let a = VoiceProfile(id:UUID(),name:"A",embeddings:[vector,vector,vector])
        let b = VoiceProfile(id:UUID(),name:"B",embeddings:[vector,vector,vector])
        XCTAssertEqual(SpeakerMath.match(vector,profiles:[a],threshold:0.75).0?.id,a.id)
        XCTAssertNil(SpeakerMath.match(vector,profiles:[a,b],threshold:0.75).0)
        XCTAssertNil(SpeakerMath.match([0,1,0],profiles:[a],threshold:0.75).0)
    }
    func testInvalidVectorsCannotMatch() {
        XCTAssertEqual(SpeakerMath.cosine([0,0],[0,0]),-1)
        XCTAssertEqual(SpeakerMath.cosine([1,0],[1]),-1)
        XCTAssertThrowsError(try SpeakerMath.normalized([.nan,1]))
    }
    func testRejectsSilentAndClippedSamples() {
        XCTAssertThrowsError(try SampleQuality.evaluate(Array(repeating:0,count:160000)))
        XCTAssertThrowsError(try SampleQuality.evaluate(Array(repeating:1,count:160000)))
    }
    func testBundledModelLoadsAndProducesFiniteEmbedding() async throws {
        let engine = SpeakerEngine()
        try await engine.prepare()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".wav")
        defer { try? FileManager.default.removeItem(at:url) }
        // A synthetic voiced signal checks model execution, not recognition accuracy.
        var pcm = Data()
        for i in 0..<160000 {
            let t = Double(i)/16000
            let value = 0.15*sin(2*Double.pi*180*t)+0.08*sin(2*Double.pi*360*t)
            var sample = Int16(value*32767).littleEndian
            withUnsafeBytes(of:&sample) { pcm.append(contentsOf:$0) }
        }
        var wav = Data("RIFF".utf8)
        func add<T:FixedWidthInteger>(_ value:T) { var v = value.littleEndian; withUnsafeBytes(of:&v) { wav.append(contentsOf:$0) } }
        add(UInt32(36+pcm.count)); wav.append(Data("WAVEfmt ".utf8));add(UInt32(16));add(UInt16(1));add(UInt16(1));add(UInt32(16000));add(UInt32(32000));add(UInt16(2));add(UInt16(16));wav.append(Data("data".utf8));add(UInt32(pcm.count));wav.append(pcm)
        try wav.write(to:url)
        let (embedding,quality,ms) = try await engine.extract(url:url)
        XCTAssertEqual(embedding.count,256)
        XCTAssertTrue(embedding.allSatisfy(\.isFinite))
        XCTAssertGreaterThan(quality.activeSeconds,3)
        XCTAssertGreaterThan(ms,0)
        XCTAssertEqual(embedding.reduce(0){$0+$1*$1},1,accuracy:0.0001)
    }
}
