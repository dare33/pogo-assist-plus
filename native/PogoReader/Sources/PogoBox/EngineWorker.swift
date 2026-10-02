import Foundation

/// The one serial queue the `CoreEngine` lives on. The engine is thread-confined and loads 2 MB of JSON and a script on
/// first use, so the app creates one worker, keeps it for the life of the process and sends every heavy call
/// (finish, refine, merge, advise, CSV) through `run`, off the main thread.
public final class EngineWorker {
    private let queue: DispatchQueue
    private let engine: CoreEngine

    public init(engine: CoreEngine = CoreEngine(), label: String = "pogo-assist.engine") {
        self.engine = engine
        queue = DispatchQueue(label: label, qos: .userInitiated)
    }

    /// Run `work` on the worker's queue with its engine.
    public func run<T>(_ work: @escaping (CoreEngine) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { cont in
            queue.async { [engine] in
                do { cont.resume(returning: try work(engine)) } catch { cont.resume(throwing: error) }
            }
        }
    }
}
