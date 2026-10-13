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

        // Activation is still running. The tap must neither fail nor move on —
        // and, once the wait is long enough to notice, say it is waiting.
        try await Task.sleep(nanoseconds: UInt64((PlaybackEngine.bufferingGrace + 0.3) * 1_000_000_000))
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

    /// `.playing` is confirmed by the engine hearing the track, and a resume —
    /// heard within milliseconds — never flashes a spinner on the way.
    func testAQuickResumeIsPlayingAtOnceWithoutASpinner() async throws {
        let url = try makeWav(seconds: 10)
        let engine = PlaybackEngine(resolver: FileResolver(url: url))
        engineUnderTest = engine

        engine.play(tracks: [Track(id: "t", title: "T", artistName: "A")])
        await eventually("audio starts") { engine.snapshot.status == .playing }
        await eventually("the position moves") { engine.snapshot.elapsed > 0.05 }

        engine.pause()
        engine.resume()
        XCTAssertEqual(engine.snapshot.status, .playing, "a resume should show as playing at once")
        for _ in 0..<10 {
            try await Task.sleep(nanoseconds: 25_000_000)
            engine.refreshNowForTesting()
            XCTAssertNotEqual(engine.snapshot.status, .buffering,
                              "a resume heard at once flashed a spinner")
        }
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

    /// Open the app, press play: the song left paused last time must play.
    ///
    /// It never did. The session is restored before any audio engine exists,
    /// so the restored song was never handed to one, and play then resumed an
    /// empty engine — silence until a skip did a real load.
    func testPressingPlayOnTheSessionRestoredAtLaunchPlaysIt() async throws {
        let url = try makeWav(seconds: 20)
        let tracks = [Track(id: "left-off", title: "L", artistName: "A"),
                      Track(id: "next", title: "N", artistName: "A")]
        let source = PlaybackEngine(resolver: FileResolver(url: url))
        source.play(tracks: tracks)
        guard let saved = source.persistentState else { return XCTFail("nothing to restore") }
        source.stop()

        // A fresh launch.
        let engine = PlaybackEngine(resolver: FileResolver(url: url))
        engineUnderTest = engine
        engine.restore(PlaybackPersistentState(queue: saved.queue, elapsed: 5))
        await engine.awaitPendingLoadsForTesting()
        XCTAssertEqual(engine.snapshot.status, .paused)

        // The progress timer runs while the app sits there before play is
        // pressed. It used to copy the position of an engine that did not hold
        // the song — there was no engine — and so wiped 0:05 to 0:00.
        engine.refreshNowForTesting()
        try await Task.sleep(nanoseconds: 100_000_000)
        engine.refreshNowForTesting()
        XCTAssertEqual(engine.snapshot.elapsed, 5, accuracy: 0.001,
                       "the restored position must survive until play is pressed")

        engine.resume()

        await eventually("the restored song plays") { engine.snapshot.status == .playing }
        XCTAssertEqual(engine.currentTrack?.id, "left-off", "it must be the song left off, not the next")
        // Seeks land on a packet boundary at or just before the request, so
        // "near 0:05", not past it. Before the engine fix this read 0:00.06.
        XCTAssertGreaterThan(engine.snapshot.elapsed, 4,
                             "it should continue from where it was left, not from the start")
        engine.stop()
    }

    /// A pause just after one song flows into the next pauses the NEXT song,
    /// and resuming continues it — not the song that just finished.
    ///
    /// The engine joins tracks on its own; the app notices on its next poll,
    /// up to half a second later. Resuming in between compared the engine's
    /// track with the app's stale one, found them different, and restarted
    /// the finished track.
    func testResumingRightAfterAGaplessJoinContinuesTheNewTrack() async throws {
        let short = try makeWav(seconds: 0.4)
        let long = try makeWav(seconds: 10)
        let engine = PlaybackEngine(resolver: PerTrackResolver(urls: ["a": short, "b": long]))
        engineUnderTest = engine
        engine.stopProgressTimerForTesting()

        engine.play(tracks: [Track(id: "a", title: "A", artistName: "X"),
                             Track(id: "b", title: "B", artistName: "X")])
        await engine.awaitPendingLoadsForTesting()
        // Let "a" end and the engine cross into "b" — without refreshing, so
        // the app has not noticed yet, exactly as between two polls.
        try await Task.sleep(nanoseconds: 1_200_000_000)
        XCTAssertEqual(engine.currentTrack?.id, "a", "precondition: the join is not yet noticed")

        engine.pause()
        engine.resume()

        XCTAssertEqual(engine.currentTrack?.id, "b", "the resume must continue the song now playing")
        await eventually("it plays") { engine.snapshot.status == .playing }
        XCTAssertEqual(engine.currentTrack?.id, "b")
        engine.stop()
    }

    /// A play abandoned while it waits for the server — a skip during launch —
    /// is cancelled before it resolves anything. Only the song the listener
    /// ended up on is resolved when the server arrives; the others used to
    /// resolve too, and for Plex each one can start a transcode on the server.
    func testPlaysSkippedWhileTheServerComesUpAreNeverResolved() async throws {
        let url = try makeWav(seconds: 10)
        let gate = SwappableResolver()
        let engine = PlaybackEngine(resolver: gate)
        engineUnderTest = engine

        engine.play(tracks: ["a", "b", "c"].map { Track(id: $0, title: $0, artistName: "X") })
        await engine.awaitPendingLoadsForTesting()
        engine.next()
        await engine.awaitPendingLoadsForTesting()
        engine.next()
        await engine.awaitPendingLoadsForTesting()

        let counting = CountingResolver(url: url)
        gate.setDelegate(counting)
        // `.playing` alone is the play being accepted; wait for it to be heard.
        await eventually("the song skipped to is heard") { engine.snapshot.elapsed > 0.05 }

        XCTAssertEqual(engine.currentTrack?.id, "c")
        XCTAssertEqual(counting.resolved, ["c"], "abandoned plays were resolved anyway")
        engine.stop()
    }

    /// A wait whose task is cancelled ends at once, with the cancellation.
    func testAWaitForTheServerEndsWhenItsTaskIsCancelled() async throws {
        let gate = SwappableResolver(readyTimeout: 30)
        let waiting = Task {
            try await gate.resolve(Track(id: "t", title: "T", artistName: "A"))
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        let started = Date()
        waiting.cancel()
        do {
            _ = try await waiting.value
            XCTFail("a cancelled wait resolved")
        } catch is CancellationError {
            XCTAssertLessThan(Date().timeIntervalSince(started), 1,
                              "cancellation should end the wait immediately")
        }
    }

    /// A paused track must stay paused when its stream fails.
    ///
    /// Recovery used to mark the player `.buffering` and then decide whether to
    /// resume by asking whether it was playing or buffering — which it had just
    /// made true. A stream dying under a song you had paused therefore started
    /// it again, and a permanent failure skipped ahead and played the next one:
    /// pause, put the phone down, and music starts by itself.
    func testAFailingStreamUnderAPausedTrackDoesNotStartPlaying() async throws {
        let dead = URL(string: "http://127.0.0.1:9/unreachable.mp3")!
        let engine = PlaybackEngine(resolver: DeadStreamResolver(url: dead))
        engineUnderTest = engine
        engine.play(tracks: [
            Track(id: "a", title: "A", artistName: "X"),
            Track(id: "b", title: "B", artistName: "X"),
        ])
        await engine.awaitPendingLoadsForTesting()
        // The engine now holds the stream. The listener pauses before the
        // failure has been noticed.
        engine.pause()

        for _ in 0..<30 {
            try await Task.sleep(nanoseconds: 100_000_000)
            engine.refreshNowForTesting()
            XCTAssertNotEqual(engine.snapshot.status, .playing,
                              "a paused track started playing on its own")
            XCTAssertNotEqual(engine.snapshot.status, .buffering,
                              "a paused player should not start loading by itself")
        }
        engine.stop()
    }

    private struct DeadStreamResolver: TrackURLResolver {
        let url: URL
        func resolve(_ track: Track) async throws -> ResolvedTrackURL {
            ResolvedTrackURL(url: url, isLocal: false)
        }
    }

    // MARK: Helpers

    private struct FileResolver: TrackURLResolver {
        let url: URL
        func resolve(_ track: Track) async throws -> ResolvedTrackURL {
            ResolvedTrackURL(url: url, isLocal: true)
        }
    }

    private struct PerTrackResolver: TrackURLResolver {
        let urls: [String: URL]
        func resolve(_ track: Track) async throws -> ResolvedTrackURL {
            ResolvedTrackURL(url: urls[track.id]!, isLocal: true)
        }
    }

    /// Records which tracks were resolved.
    private final class CountingResolver: TrackURLResolver, @unchecked Sendable {
        private let lock = NSLock()
        private var ids: [String] = []
        let url: URL
        init(url: URL) { self.url = url }
        var resolved: [String] { lock.lock(); defer { lock.unlock() }; return ids }
        func resolve(_ track: Track) async throws -> ResolvedTrackURL {
            lock.lock(); ids.append(track.id); lock.unlock()
            return ResolvedTrackURL(url: url, isLocal: true)
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
