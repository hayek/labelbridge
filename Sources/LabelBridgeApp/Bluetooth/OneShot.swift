/// A continuation that resumes at most once — from a delegate callback or from a timeout, whichever is first.
@MainActor
final class OneShot<T> {
    private var continuation: CheckedContinuation<T, Error>?
    var isPending: Bool { continuation != nil }

    func resume(_ value: T) { continuation?.resume(returning: value); continuation = nil }
    func fail(_ error: Error) { continuation?.resume(throwing: error); continuation = nil }

    /// Calls `install` with this one-shot, then waits for it; fails with `error` after `timeout`.
    func wait(timeout: Duration, error: Error, install: (OneShot<T>) -> Void, onTimeout: @escaping () -> Void = {}) async throws -> T {
        try await withCheckedThrowingContinuation { c in
            continuation = c
            install(self)
            Task { @MainActor in
                try? await Task.sleep(for: timeout)
                if self.isPending { onTimeout(); self.fail(error) }
            }
        }
    }
}
