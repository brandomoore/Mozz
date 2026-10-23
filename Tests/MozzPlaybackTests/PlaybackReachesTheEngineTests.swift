import MozzCore
import XCTest

@testable import MozzPlayback

/// Proof that playback actually reaches the shared audio engine.
///
/// Every other test in this target uses a resolver that returns
/// `/dev/null/<id>.m4a`, which cannot be opened — so the engine is never
/// constructed, never handed a stream, and never asked to make a sound. Those
/// tests are still worth having: they cover queue behaviour, transport
/// direction and event emission, which is most of what the class does.
///
/// But it means the entire suite passed unchanged when `AVQueuePlayer` was
/// removed and the Rust engine put in its place. A test suite that cannot tell
/// which audio engine is installed is not evidence the swap worked. This is the
/// test that can tell.
@MainActor
final class PlaybackReachesTheEngineTests: XCTestCase {
    /// Hands back a real file on disk, so the engine has something to decode.
    private struct RealFileResolver: TrackURLResolver {
        let url: URL
        func resolve(_ track: Track) async throws -> ResolvedTrackURL {
            ResolvedTrackURL(url: url, isLocal: true)
        }
    }

    private struct FileByTrackResolver: TrackURLResolver {
        let files: [String: URL]
        func resolve(_ track: Track) async throws -> ResolvedTrackURL {
            guard let url = files[track.id] else { throw MozzError.notFound }
            return ResolvedTrackURL(url: url, isLocal: true)
        }
    }

    private var written: [URL] = []

    override func tearDown() {
        for url in written { try? FileManager.default.removeItem(at: url) }
        written = []
        super.tearDown()
    }

    /// A mono 8 kHz WAV of `seconds` at a steady level, written to a temp file.
    ///
    /// Built here rather than committed, so the test carries its own fixture and
    /// the expected samples are known exactly.
    private func makeWav(seconds: Double) throws -> URL {
        let rate = 8_000
        let frames = Int(Double(rate) * seconds)
        var bytes = Data()

        func u32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { bytes.append(contentsOf: $0) } }
        func u16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { bytes.append(contentsOf: $0) } }

        let dataBytes = UInt32(frames * 2)
        bytes.append(contentsOf: Array("RIFF".utf8)); u32(36 + dataBytes)
        bytes.append(contentsOf: Array("WAVEfmt ".utf8)); u32(16)
        u16(1); u16(1); u32(UInt32(rate)); u32(UInt32(rate * 2)); u16(2); u16(16)
        bytes.append(contentsOf: Array("data".utf8)); u32(dataBytes)
        for _ in 0..<frames { u16(UInt16(bitPattern: 8_000)) }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mozz-playback-\(UUID().uuidString).wav")
        try bytes.write(to: url)
        written.append(url)
        return url
    }

    /// Wait for something the decode thread produces, rather than assuming a
    /// speed this machine may not have.
    private func eventually(
        _ what: String, _ condition: () -> Bool,
        file: StaticString = #filePath, line: UInt = #line
    ) async {
        for _ in 0..<400 {
            if condition() { return }
            await settle(0.01)
        }
        XCTFail("timed out waiting for: \(what)", file: file, line: line)
    }

    /// Let real time pass, then refresh.
    ///
    /// The snapshot is only as fresh as the last timer tick, so `Task.sleep`
    /// alone advances the clock while the reported position sits frozen at
    /// whatever the last tick saw — a convincing false failure. Turning the
    /// main run loop instead is worse: it blocks the async work that loading a
    /// track depends on, so playback never starts at all. Both of those were
    /// tried before this.
    ///
    /// Sleeping lets the decode thread genuinely run; the explicit refresh then
    /// reads what it produced, without racing a timer the test cannot see.
    private func settle(_ seconds: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        engineUnderTest?.refreshNowForTesting()
    }

    private weak var engineUnderTest: PlaybackEngine?

    /// The one that would have failed if the swap had been wired up wrongly:
    /// real bytes go in and the engine reports a position that moves.
    func testPlayingARealFileAdvancesThePosition() async throws {
        let url = try makeWav(seconds: 10)
        let engine = PlaybackEngine(resolver: RealFileResolver(url: url))
        engineUnderTest = engine

        engine.play(tracks: [Track(id: "t0", title: "T", artistName: "A")])

        await eventually("playback starts") { engine.snapshot.status == .playing }
        await eventually("the position moves") { engine.snapshot.elapsed > 0.05 }

        // And it keeps moving, rather than reporting one non-zero value forever.
        let early = engine.snapshot.elapsed
        await settle(0.6)
        XCTAssertGreaterThan(
            engine.snapshot.elapsed, early,
            "position stalled at \(early); the engine is not actually decoding")

        engine.stop()
    }

    /// Pausing has to stop the position moving. A player that reports progress
    /// while paused is one whose position comes from a clock rather than from
    /// the audio, which is the specific mistake this architecture exists to
    /// avoid.
    func testPausingStopsThePositionMoving() async throws {
        let url = try makeWav(seconds: 10)
        let engine = PlaybackEngine(resolver: RealFileResolver(url: url))
        engineUnderTest = engine

        engine.play(tracks: [Track(id: "t0", title: "T", artistName: "A")])
        await eventually("the position moves") { engine.snapshot.elapsed > 0.05 }

        engine.pause()
        await settle(0.3)
        let atPause = engine.snapshot.elapsed
        await settle(0.6)

        XCTAssertEqual(
            engine.snapshot.elapsed, atPause, accuracy: 0.15,
            "position kept moving while paused, so it is not coming from the audio")

        engine.stop()
    }

    /// A file that cannot be decoded must be reported rather than leaving a
    /// player that silently sits at zero — which is indistinguishable from a
    /// server that is merely slow.
    func testAFileThatIsNotAudioIsReportedRatherThanHanging() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mozz-not-audio-\(UUID().uuidString).bin")
        try Data(repeating: 9, count: 4_096).write(to: url)
        written.append(url)

        let engine = PlaybackEngine(resolver: RealFileResolver(url: url))
        engineUnderTest = engine
        engine.play(tracks: [Track(id: "t0", title: "T", artistName: "A")])

        await eventually("the failure surfaces") {
            engine.lastFailure != nil && engine.snapshot.status == .paused
        }
        XCTAssertEqual(engine.currentTrack?.id, "t0")
        XCTAssertEqual(engine.lastFailure?.skippedTracks, 0)
        engine.stop()
    }

    func testDecoderFailuresStopAfterEightAttemptsEvenWhenRepeating() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mozz-not-audio-\(UUID().uuidString).bin")
        try Data(repeating: 9, count: 4_096).write(to: url)
        written.append(url)

        for mode in [MozzPlayback.RepeatMode.off, .all, .one] {
            let engine = PlaybackEngine(resolver: RealFileResolver(url: url))
            engineUnderTest = engine
            engine.setRepeatMode(mode)
            engine.play(tracks: (0..<50).map {
                Track(id: "t\($0)", title: "T", artistName: "A")
            })
            await eventually("decoder failures stop the queue") {
                engine.snapshot.status == .paused && engine.lastFailure != nil
            }
            XCTAssertEqual(engine.lastFailure?.skippedTracks, 7)
            let failedTrack = engine.currentTrack?.id
            await settle(0.15)
            XCTAssertEqual(engine.currentTrack?.id, failedTrack, "a latched failure must not keep skipping")
            XCTAssertEqual(engine.snapshot.status, .paused)
            engine.stop()
        }
    }

    func testActualAudioClearsAPreviousDecoderFailure() async throws {
        let invalid = FileManager.default.temporaryDirectory
            .appendingPathComponent("mozz-not-audio-\(UUID().uuidString).bin")
        try Data(repeating: 9, count: 4_096).write(to: invalid)
        written.append(invalid)
        let valid = try makeWav(seconds: 10)
        let engine = PlaybackEngine(resolver: FileByTrackResolver(files: ["bad": invalid, "good": valid]))
        engineUnderTest = engine
        engine.play(tracks: [Track(id: "bad", title: "T", artistName: "A")])
        await eventually("invalid audio is reported") { engine.lastFailure != nil }

        engine.play(tracks: [Track(id: "good", title: "T", artistName: "A")])
        await eventually("valid audio reaches the output") { engine.snapshot.elapsed > 0.05 }
        XCTAssertNil(engine.lastFailure)
        engine.stop()
    }

    /// Stopping must actually stop the audio, not just the reporting.
    func testStoppingHaltsTheEngine() async throws {
        let url = try makeWav(seconds: 10)
        let engine = PlaybackEngine(resolver: RealFileResolver(url: url))
        engineUnderTest = engine

        engine.play(tracks: [Track(id: "t0", title: "T", artistName: "A")])
        await eventually("the position moves") { engine.snapshot.elapsed > 0.05 }

        engine.stop()
        await settle(0.3)

        XCTAssertEqual(engine.snapshot.status, .idle)
        XCTAssertNil(engine.currentTrack)
    }
}
