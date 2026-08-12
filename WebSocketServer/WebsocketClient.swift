import Foundation

/// A minimal WebSocket client.
///
/// Ownership rule: `connect()` starts the receive loop, and the loop sustains
/// itself by re-arming inside its own completion handler. Nothing else calls
/// `receive()`. That single rule is what keeps the loop alive — the previous
/// version had two entry points racing each other, which could leave the loop
/// un-armed and messages stuck in the task's internal buffer.
final class WebsocketClient: NSObject, ClientProtocol {

    weak var delegate: ClientDelegate?

    private var session: URLSession!
    private var task: URLSessionWebSocketTask?

    override init() {
        super.init()
        // Own the session so socket open/close callbacks arrive on the delegate.
        // URLSession.shared can't be used here — it has no delegate.
        session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }

    // MARK: - ClientProtocol

    func connect(to url: URL) async {
        disconnect()                                   // tear down any previous socket
        task = session.webSocketTask(with: url)
        task?.resume()
        receive()                                      // the only call to receive()
    }

    func disconnect() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    func send(data: Data) async {
        await send(.data(data))
    }

    func send(message: String) async {
        await send(.string(message))
    }

    // MARK: - Private

    private func send(_ message: URLSessionWebSocketTask.Message) async {
        guard let task, task.state == .running else {
            delegate?.onConnectionStatus(status: "Not connected — message not sent")
            return
        }
        do {
            try await task.send(message)
        } catch {
            SCLogger.logger.error(message: "Send failed", error: error, category: .Network)
            delegate?.onConnectionStatus(status: "Send failed: \(error.localizedDescription)")
        }
    }

    /// Arms a single receive. The completion re-arms before doing any work, so
    /// nothing downstream — a throw, an early return, a slow delegate call —
    /// can break the loop.
    private func receive() {
        task?.receive { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let message):
                self.receive()                          // re-arm FIRST

                switch message {
                case .data(let data):
                    SCLogger.logger.info(
                        message: "Received data: \(String(data: data, encoding: .utf8) ?? "<binary>")",
                        category: .Network
                    )
                    self.delegate?.onReceive(data: data)

                case .string(let text):
                    SCLogger.logger.info(message: "Received string: \(text)", category: .Network)
                    self.delegate?.onReceive(message: text)

                @unknown default:
                    break
                }

            case .failure(let error):
                // Terminal: once a receive fails the task is finished, so we do
                // NOT re-arm. Re-arming here would spin against a dead socket.
                SCLogger.logger.error(message: "Receive failed", error: error, category: .Network)
                self.delegate?.onConnectionStatus(status: "Disconnected: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - URLSessionWebSocketDelegate

// Connection state is only meaningful here. Reading `task.state` right after
// `resume()` reports the pre-handshake state, and `closeReason` is nil until
// the socket actually closes.
extension WebsocketClient: URLSessionWebSocketDelegate {

    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        SCLogger.logger.info(message: "WebSocket connected", category: .Network)
        delegate?.onConnectionStatus(status: "Connected")
    }

    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
                    reason: Data?) {
        let text = reason.flatMap { String(data: $0, encoding: .utf8) } ?? "none"
        SCLogger.logger.info(message: "WebSocket closed: \(closeCode.rawValue) — \(text)", category: .Network)
        delegate?.onConnectionStatus(status: "Disconnected (code \(closeCode.rawValue)): \(text)")
    }
}
