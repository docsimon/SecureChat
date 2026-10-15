//
//  RelayClient.swift
//  SessionKit
//
//  The WebSocket to the relay (session-workflow.md, "Relay"). Moves opaque
//  fixed-size frames; it knows nothing about sessions.
//

import Foundation

/// What `SessionService` needs from a relay connection: fixed-size frames
/// in and out, and the connection state. `RelayClient` is the real one.
@MainActor
public protocol RelayTransport: AnyObject {
    var state: RelayClient.State { get }
    var onStateChange: ((RelayClient.State) -> Void)? { get set }
    var onFrame: ((Data) -> Void)? { get set }
    func connect()
    func disconnect()
    /// Sends in order. A failure means the connection is gone.
    func send(_ frames: [Data]) async throws
}

@MainActor
public final class RelayClient: NSObject {

    public enum Credential: Sendable, Equatable {
        /// From the Auth Server's `POST /session`.
        case sessionToken(String)
        /// Development relays only (`RELAY_DEV_CLAIMED_ACCOUNTS`): no token.
        case developmentAccount(UUID)
    }

    public enum State: Equatable, Sendable {
        case disconnected
        case connecting
        case connected
    }

    public private(set) var state: State = .disconnected {
        didSet { if state != oldValue { onStateChange?(state) } }
    }
    public var onStateChange: ((State) -> Void)?
    public var onFrame: ((Data) -> Void)?

    private let url: URL
    private let credential: Credential
    private var session: URLSession?
    private var task: URLSessionWebSocketTask?

    public init(url: URL, credential: Credential) {
        self.url = url
        self.credential = credential
    }

    public func connect() {
        guard state == .disconnected else { return }
        var request = URLRequest(url: url)
        switch credential {
        case .sessionToken(let token):
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        case .developmentAccount(let account):
            request.setValue(account.uuidString, forHTTPHeaderField: "X-Dev-Account")
        }
        // One session per connection: a URLSession keeps its delegate alive
        // until invalidated, and `disconnect` invalidates it.
        let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: .main)
        let task = session.webSocketTask(with: request)
        task.maximumMessageSize = RelayFrame.size
        self.session = session
        self.task = task
        state = .connecting
        task.resume()
        receive(on: task)
    }

    public func disconnect() {
        task?.cancel(with: .normalClosure, reason: nil)
        session?.invalidateAndCancel()
        task = nil
        session = nil
        state = .disconnected
    }

    /// Sends in order. A failure means the connection is gone.
    public func send(_ frames: [Data]) async throws {
        guard let task, state == .connected else { throw RelayClientError.notConnected }
        for frame in frames {
            try await task.send(.data(frame))
        }
    }

    /// The only caller of `receive`: each completion re-arms the next one.
    private func receive(on task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            Task { @MainActor in
                guard let self, self.task === task else { return }
                switch result {
                case .success(.data(let data)):
                    self.onFrame?(data)
                    self.receive(on: task)
                case .success:
                    // The relay never sends text; ignore it and keep reading.
                    self.receive(on: task)
                case .failure:
                    self.disconnect()
                }
            }
        }
    }
}

extension RelayClient: URLSessionWebSocketDelegate {
    nonisolated public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                                       didOpenWithProtocol protocol: String?) {
        Task { @MainActor in
            if self.task === webSocketTask { self.state = .connected }
        }
    }

    nonisolated public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                                       didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        Task { @MainActor in
            if self.task === webSocketTask { self.disconnect() }
        }
    }

    nonisolated public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        Task { @MainActor in
            if self.task === task { self.disconnect() }
        }
    }
}

extension RelayClient: RelayTransport {}

public enum RelayClientError: Error, Equatable {
    case notConnected
}
