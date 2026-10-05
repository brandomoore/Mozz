import Foundation
import MozzCore
@testable import MozzApp
@testable import MozzPlayback
import XCTest

#if DEBUG
/// A song tapped before the server is ready has to wait for it, not fail.
///
/// On a cold launch the library is on screen from the local database seconds
/// before the server has been activated — capability detection, and for Plex
/// possibly asking the account for a working address. The resolver used to
/// throw "No active server" for the whole of that window, and the failure
/// handler then skipped through the queue failing on each track; skipping by
/// hand a few seconds later appeared to fix it, because by then activation had
/// finished. Nothing on screen said any of this was happening.
@MainActor
final class ColdStartPlaybackTests: XCTestCase {
    private var written: [URL] = []
    private weak var engineUnderTest: PlaybackEngine?

    override func tearDown() {
        for url in written { try? FileManager.default.removeItem(at: url) }
        written.removeAll()
        super.tearDown()
    }

    /// The reported scenario, end to end against the real engine.
    func testASongTappedBeforeTheServerIsReadyPlaysOnceItIs() async throws {
        let url = try makeWav(seconds: 10)
        let gate = SwappableResolver()
        let engine = PlaybackEngine(resolver: gate)
        engineUnderTest = engine

        engine.play(tracks: [
            Track(id: "first", title: "First", artistName: "A"),
            Track(id: "second", title: "Second", artistName: "A"),
        ])

        // Activation is still running. The tap must neither fail nor move on.
        try await Task.sleep(nanoseconds: 300_000_000)
        engine.refreshNowForTesting()
        XCTAssertEqual(engine.snapshot.status, .buffering,
                       "a play waiting on the server should say it is waiting")
        XCTAssertNil(engine.lastFailure, "waiting for the server is not a failure")
        XCTAssertEqual(engine.currentTrack?.id, "first",
                       "it must not skip ahead while the server comes up")

        // Activation finishes.
        gate.setDelegate(FileResolver(url: url))

        await eventually("the tapped song plays") { engine.snapshot.status == .playing }
        XCTAssertEqual(engine.currentTrack?.id, "first")
        await eventually("sound is actually coming out") { engine.snapshot.elapsed > 0.05 }
        engine.stop()
    }

    /// `.playing` means audio, not "a URL was handed over". Status stays
    /// `.buffering` until the playhead moves, so the player can show a spinner
    /// instead of a pause button over silence.
    func testStatusIsBufferingUntilThePlayheadMoves() async throws {
        let url = try makeWav(seconds: 10)
        let engine = PlaybackEngine(resolver: FileResolver(url: url))
        engineUnderTest = engine

        engine.play(tracks: [Track(id: "t", title: "T", artistName: "A")])
        XCTAssertEqual(engine.snapshot.status, .buffering)

        await eventually("audio starts") { engine.snapshot.status == .playing }
        XCTAssertGreaterThan(engine.snapshot.elapsed, 0,
                             "it said playing before the playhead had moved")
        engine.stop()
    }

    /// A server that never comes up must not leave the play waiting forever.
    func testAPlayGivesUpWhenTheServerNeverArrives() async {
        let gate = SwappableResolver(readyTimeout: 0.2)
        do {
            _ = try await gate.resolve(Track(id: "t", title: "T", artistName: "A"))
            XCTFail("resolved with no server")
        } catch {
            // Expected: the reason is reported rather than hanging.
        }
    }

    /// A delegate installed before the request is used at once, without waiting.
    func testAReadyServerIsUsedImmediately() async throws {
        let url = try makeWav(seconds: 1)
        let gate = SwappableResolver(readyTimeout: 0.01)
        gate.setDelegate(FileResolver(url: url))
        let resolved = try await gate.resolve(Track(id: "t", title: "T", artistName: "A"))
        XCTAssertEqual(resolved.url, url)
    }

    // MARK: Helpers

    private struct FileResolver: TrackURLResolver {
        let url: URL
        func resolve(_ track: Track) async throws -> ResolvedTrackURL {
            ResolvedTrackURL(url: url, isLocal: true)
        }
    }

    /// The snapshot only moves on a timer tick, so poll by refreshing it
    /// explicitly after letting the decode thread run.
    private func eventually(
        _ what: String, _ condition: () -> Bool,
        file: StaticString = #filePath, line: UInt = #line
    ) async {
        for _ in 0..<400 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
            engineUnderTest?.refreshNowForTesting()
        }
        XCTFail("timed out waiting for: \(what)", file: file, line: line)
    }

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
            .appendingPathComponent("mozz-coldstart-\(UUID().uuidString).wav")
        try bytes.write(to: url)
        written.append(url)
        return url
    }
}
#endif
