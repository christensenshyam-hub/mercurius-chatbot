import Foundation

/// How far a request got before it failed. A timeout means different things
/// at each step (AUD-32):
/// - never connected (no TCP + TLS) on a working path: the network is
///   swallowing the traffic, which is what a school filter's silent drop does;
/// - connected, but no response headers: the server is slow to answer (it
///   awaits the database and its gate before any header goes out), so
///   "the server may be busy" is right;
/// - the response had started: the connection died under a live reply.
public enum ConnectionPhase: Sendable, Equatable {
    /// Nothing to read: no network transaction (a stubbed or cached load) or
    /// metrics that never arrived. Classify by the error code alone.
    case unknown
    /// A network load that never finished connecting (TCP and, for https, TLS).
    case connecting
    /// Connected and the request went out; no response headers yet.
    case awaitingResponse
    /// The response headers arrived.
    case receivingResponse

    /// The phase of the task's last network transaction (the final hop after
    /// any redirect).
    public init(metrics: URLSessionTaskMetrics) {
        let network = metrics.transactionMetrics.last { $0.resourceFetchType == .networkLoad }
        self = network.map { ConnectionTimeline($0).phase } ?? .unknown
    }
}

/// The few facts of one `URLSessionTaskTransactionMetrics` the phase depends
/// on. A plain value, because the metrics classes can't be built in a test.
struct ConnectionTimeline: Equatable, Sendable {
    var isNetworkLoad: Bool
    var isSecure: Bool
    var isReusedConnection: Bool
    var connectEnded: Bool
    var secureConnectionEnded: Bool
    var requestStarted: Bool
    var responseStarted: Bool

    init(
        isNetworkLoad: Bool = true,
        isSecure: Bool = true,
        isReusedConnection: Bool = false,
        connectEnded: Bool = false,
        secureConnectionEnded: Bool = false,
        requestStarted: Bool = false,
        responseStarted: Bool = false
    ) {
        self.isNetworkLoad = isNetworkLoad
        self.isSecure = isSecure
        self.isReusedConnection = isReusedConnection
        self.connectEnded = connectEnded
        self.secureConnectionEnded = secureConnectionEnded
        self.requestStarted = requestStarted
        self.responseStarted = responseStarted
    }

    init(_ transaction: URLSessionTaskTransactionMetrics) {
        self.init(
            isNetworkLoad: transaction.resourceFetchType == .networkLoad,
            isSecure: transaction.request.url?.scheme?.lowercased() == "https",
            isReusedConnection: transaction.isReusedConnection,
            connectEnded: transaction.connectEndDate != nil,
            secureConnectionEnded: transaction.secureConnectionEndDate != nil,
            requestStarted: transaction.requestStartDate != nil,
            responseStarted: transaction.responseStartDate != nil
        )
    }

    var phase: ConnectionPhase {
        guard isNetworkLoad else { return .unknown }
        if responseStarted { return .receivingResponse }
        // A reused connection has no connect dates of its own; a request that
        // started going out had a connection to go out on.
        let connected = isReusedConnection
            || requestStarted
            || (connectEnded && (!isSecure || secureConnectionEnded))
        return connected ? .awaitingResponse : .connecting
    }
}

/// Collects a task's metrics as its per-task delegate, for the phase a
/// failure happened in. URLSession hands the metrics over before the task
/// completes, so they are in by the time the `data(for:delegate:)` call throws.
final class TaskMetricsRecorder: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: ConnectionPhase = .unknown

    var phase: ConnectionPhase {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didFinishCollecting metrics: URLSessionTaskMetrics
    ) {
        let phase = ConnectionPhase(metrics: metrics)
        lock.lock()
        recorded = phase
        lock.unlock()
    }
}
