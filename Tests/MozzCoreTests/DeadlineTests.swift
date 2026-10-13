import Foundation
@testable import MozzCore
import XCTest

final class DeadlineTests: XCTestCase {
    func testWorkThatFinishesInTimeReturnsItsResult() async {
        let value = await withDeadline(seconds: 5, fallback: 0) { 42 }
        XCTAssertEqual(value, 42)
    }

    /// The case a deadline exists for: work stuck where cancellation cannot
    /// reach it — here, a blocking call on another thread behind a continuation,
    /// the shape of a `sendto` that never returns. A task group racing it
    /// against a sleep waited for it anyway; this must not.
    func testWorkStuckWhereCancellationCannotReachIsAbandonedAtTheDeadline() async {
        let started = Date()
        let value = await withDeadline(seconds: 0.2, fallback: -1) {
            await withCheckedContinuation { (continuation: CheckedContinuation<Int, Never>) in
                DispatchQueue.global().async {
                    Thread.sleep(forTimeInterval: 5)
                    continuation.resume(returning: 1)
                }
            }
        }
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertEqual(value, -1)
        XCTAssertLessThan(elapsed, 1.5, "the deadline waited for the stuck work (\(elapsed)s)")
    }

    /// Cancelling the caller ends the wait at once.
    func testCancellingTheCallerReturnsTheFallbackAtOnce() async {
        let waiting = Task {
            await withDeadline(seconds: 30, fallback: "gave up") {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                return "finished"
            }
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
        let started = Date()
        waiting.cancel()
        let value = await waiting.value
        XCTAssertEqual(value, "gave up")
        XCTAssertLessThan(Date().timeIntervalSince(started), 1)
    }

    /// Work that can hear cancellation is told to stop when the deadline wins.
    func testTheWorkIsCancelledWhenTheDeadlinePasses() async {
        let cancelled = expectation(description: "the work was cancelled")
        _ = await withDeadline(seconds: 0.1, fallback: 0) {
            do {
                try await Task.sleep(nanoseconds: 10_000_000_000)
            } catch {
                cancelled.fulfill()
            }
            return 1
        }
        await fulfillment(of: [cancelled], timeout: 2)
    }
}
