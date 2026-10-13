import Foundation

/// Run `operation`, and give up on it after `seconds`: return its result if it
/// finishes in time, otherwise `fallback` — without waiting for it to finish.
///
/// The obvious way to write a timeout is a task group racing the work against a
/// sleep and taking whichever comes first, and it does not work for the case a
/// timeout exists for. A task group cannot return until every child has
/// finished, so when the work is stuck somewhere cancellation cannot reach — a
/// blocking system call, a continuation nobody resumes — the "timeout" waits
/// for it too. LAN discovery was written that way: a `sendto` that never
/// returned held the core call, and the test waiting on it, for six days.
///
/// Here the work runs in an unstructured task that this function does not
/// wait for. At the deadline the caller gets `fallback` and the work is told to
/// cancel; if it cannot hear that, it finishes on its own later and its result
/// is dropped. That is the right trade for anything where an answer late is no
/// better than no answer — which is what a deadline says.
///
/// Cancelling the caller also returns `fallback` at once.
public func withDeadline<T: Sendable>(
    seconds: TimeInterval,
    fallback: T,
    _ operation: @escaping @Sendable () async -> T
) async -> T {
    let gate = FirstAnswer<T>()
    return await withTaskCancellationHandler {
        await withCheckedContinuation { continuation in
            gate.waiting(continuation)
            let work = Task {
                gate.answer(await operation())
            }
            gate.onAnswer { work.cancel() }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
                gate.answer(fallback)
            }
        }
    } onCancel: {
        gate.answer(fallback)
    }
}

/// Resumes a continuation with whichever answer arrives first, exactly once.
private final class FirstAnswer<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Never>?
    /// An answer that arrived before there was a continuation to give it to —
    /// the caller cancelled before the wait began.
    private var early: T?
    private var answered = false
    private var whenAnswered: [() -> Void] = []

    func waiting(_ continuation: CheckedContinuation<T, Never>) {
        lock.lock()
        if answered, let early {
            lock.unlock()
            continuation.resume(returning: early)
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    func answer(_ value: T) {
        lock.lock()
        guard !answered else { lock.unlock(); return }
        answered = true
        let continuation = self.continuation
        self.continuation = nil
        if continuation == nil { early = value }
        let callbacks = whenAnswered
        whenAnswered = []
        lock.unlock()
        continuation?.resume(returning: value)
        callbacks.forEach { $0() }
    }

    /// Run `action` once an answer exists — now, if one already does.
    func onAnswer(_ action: @escaping () -> Void) {
        lock.lock()
        if answered {
            lock.unlock()
            action()
            return
        }
        whenAnswered.append(action)
        lock.unlock()
    }
}
