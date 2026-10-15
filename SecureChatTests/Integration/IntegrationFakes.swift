//
//  IntegrationFakes.swift
//  SecureChatTests
//
//  The outside world for the integration tests: Apple's App Attest service,
//  the Keychain item AppAttestKit keeps, the Auth Server on the network, and
//  the relay.
//  Everything between them is the code that ships.
//

import Foundation
@_spi(Testing) import AppAttestKit
import RegistrationKit
import SessionKit

/// Stands in for `DCAppAttestService`: always supported, never fails, and
/// answers `attestKey` with an object shaped like Apple's development one
/// (the aaguid is `appattestdevelop`), so the app's environment check reads
/// it the way it reads a real one.
struct FakeAppleAttestService: AttestServicing {
    var isSupported: Bool { true }

    func generateKey() async throws -> String {
        UUID().uuidString
    }

    func attestKey(_ keyId: String, clientDataHash: Data) async throws -> Data {
        Self.developmentAttestation
    }

    func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data {
        Data(clientDataHash.reversed())
    }

    /// CBOR `{"fmt": "apple-appattest", "attStmt": {}, "authData": <53 bytes>}`.
    /// authData: rpIdHash (32) + flags (1) + counter (4) + aaguid (16).
    static let developmentAttestation: Data = {
        func text(_ string: String) -> Data { Data([0x60 | UInt8(string.utf8.count)]) + Data(string.utf8) }
        let authData = Data(count: 32) + Data([0x40]) + Data(count: 4) + Data("appattestdevelop".utf8)
        return Data([0xA3])
            + text("fmt") + text("apple-appattest")
            + text("attStmt") + Data([0xA0])
            + text("authData") + Data([0x58, UInt8(authData.count)]) + authData
    }()
}

/// Stands in for AppAttestKit's Keychain-backed store.
final class InMemoryAttestationKeyStore: AttestationKeyStore, @unchecked Sendable {
    private let lock = NSLock()
    private var keyId: String?
    private var isAttested = false
    private var attestation: (object: Data, challenge: Data)?

    func loadKeyId() throws -> String? { lock.withLock { keyId } }
    func store(keyId: String) throws { lock.withLock { self.keyId = keyId } }
    func loadIsAttested() throws -> Bool { lock.withLock { isAttested } }
    func store(isAttested: Bool) throws { lock.withLock { self.isAttested = isAttested } }
    func loadAttestation() throws -> (object: Data, challenge: Data)? { lock.withLock { attestation } }
    func store(attestation: Data, challenge: Data) throws { lock.withLock { self.attestation = (attestation, challenge) } }
    func clearAttestation() throws { lock.withLock { attestation = nil } }
    func clear() throws {
        lock.withLock {
            keyId = nil
            isAttested = false
            attestation = nil
        }
    }
}

/// Stands in for the Auth Server's `/challenge`, `/register`, `/session/nonce`
/// and `/session`, reached through the real `RealAttestationTransport` and
/// `SessionClient` over a `URLSession` whose requests never leave the
/// process. Keeps the server's rules that the app depends on: a challenge is
/// issued for one identity key and used once, `/register` must carry that
/// same key, only development attestations are accepted (the docker server
/// runs with `APPATTEST_ENVIRONMENT=development`), a session nonce is used
/// once, and a token is only issued to a registered account.
/// It does not verify Apple's signatures: nothing it receives was signed.
final class FakeAuthServer: @unchecked Sendable {

    let baseURL: URL
    let session: URLSession

    private let lock = NSLock()
    /// Challenge (base64) → the identity key (base64) it was issued for.
    private var openChallenges: [String: String] = [:]
    /// Identity key (base64) → account id.
    private var accounts: [String: String] = [:]
    private var openNonces: Set<String> = []
    /// Session token → account id.
    private var tokens: [String: UUID] = [:]

    init() {
        let host = "auth-\(UUID().uuidString.lowercased()).test"
        baseURL = URL(string: "http://\(host)")!
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FakeAuthServerProtocol.self]
        session = URLSession(configuration: configuration)
        FakeAuthServerProtocol.register(self, host: host)
    }

    /// The account id this server gave the device with this identity key.
    func accountID(forIdentityKey key: Data) -> String? {
        lock.withLock { accounts[key.base64EncodedString()] }
    }

    /// What the relay asks the Auth Server's Redis: whose token is this.
    func account(forToken token: String) -> UUID? {
        lock.withLock { tokens[token] }
    }

    var issuedTokenCount: Int {
        lock.withLock { tokens.count }
    }

    fileprivate func respond(to request: URLRequest) -> (status: Int, body: [String: String]) {
        lock.withLock {
            switch (request.httpMethod ?? "GET", request.url?.path) {
            case ("GET", "/challenge"):
                let items = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems
                guard let key = items?.first(where: { $0.name == "identityPublicKey" })?.value,
                      Data(base64Encoded: key)?.count == 32 else {
                    return (400, ["error": "identity_key_invalid"])
                }
                let challenge = Data((0..<32).map { _ in UInt8.random(in: 0...255) }).base64EncodedString()
                openChallenges[challenge] = key
                return (200, ["challenge": challenge])

            case ("POST", "/register"):
                guard let body = Self.body(of: request),
                      let fields = try? JSONDecoder().decode([String: String].self, from: body),
                      let challenge = fields["challenge"], let key = fields["identityPublicKey"],
                      let attestation = fields["attestation"].flatMap({ Data(base64Encoded: $0) }) else {
                    return (400, ["error": "malformed"])
                }
                guard let issuedFor = openChallenges.removeValue(forKey: challenge) else {
                    return (400, ["error": "challenge_invalid_or_expired"])
                }
                guard issuedFor == key else { return (400, ["error": "identity_mismatch"]) }
                guard AttestationEnvironmentHint.environment(of: attestation) == .development else {
                    return (400, ["error": "attestation_invalid"])
                }
                let account = accounts[key] ?? UUID().uuidString.lowercased()
                accounts[key] = account
                return (200, ["accountUuid": account])

            case ("GET", "/session/nonce"):
                let nonce = Data((0..<32).map { _ in UInt8.random(in: 0...255) }).base64EncodedString()
                openNonces.insert(nonce)
                return (200, ["challenge": nonce])

            case ("POST", "/session"):
                guard let body = Self.body(of: request),
                      let fields = try? JSONDecoder().decode([String: String].self, from: body),
                      let nonce = fields["nonce"], fields["assertion"] != nil,
                      let account = fields["accountUuid"].flatMap(UUID.init(uuidString:)) else {
                    return (400, ["error": "malformed"])
                }
                guard openNonces.remove(nonce) != nil else { return (400, ["error": "nonce_invalid_or_expired"]) }
                guard accounts.values.contains(where: { UUID(uuidString: $0) == account }) else {
                    return (404, ["error": "account_not_found"])
                }
                let token = UUID().uuidString
                tokens[token] = account
                return (200, ["sessionToken": token, "accountUuid": account.uuidString.lowercased()])

            default:
                return (404, ["error": "not_found"])
            }
        }
    }

    /// `URLSession` hands a protocol the body as a stream, not `httpBody`.
    private static func body(of request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

private final class FakeAuthServerProtocol: URLProtocol, @unchecked Sendable {

    private static let lock = NSLock()
    nonisolated(unsafe) private static var servers: [String: FakeAuthServer] = [:]

    static func register(_ server: FakeAuthServer, host: String) {
        lock.withLock { servers[host] = server }
    }

    private static func server(for request: URLRequest) -> FakeAuthServer? {
        lock.withLock { request.url?.host.flatMap { servers[$0] } }
    }

    override class func canInit(with request: URLRequest) -> Bool { server(for: request) != nil }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let server = Self.server(for: request), let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        let (status, body) = server.respond(to: request)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: (try? JSONEncoder().encode(body)) ?? Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Stands in for the relay (RelayServer/): routes fixed-size frames between
/// the `SessionService`s of the devices under test, in process. Keeps the
/// relay's rules: credentials checked at connect (a token the fake Auth
/// Server issued, or a claimed account when `acceptsClaimedAccounts`), and,
/// like the real one, a refused client sees the socket open and then close;
/// the sender's id written into every delivered frame, "peer unavailable"
/// for an account with no connection, nothing stored.
@MainActor
final class InProcessRelay {

    private let server: FakeAuthServer
    private let acceptsClaimedAccounts: Bool
    /// Routing id → the open connection for it.
    private var connections: [Data: Connection] = [:]

    init(server: FakeAuthServer, acceptsClaimedAccounts: Bool = false) {
        self.server = server
        self.acceptsClaimedAccounts = acceptsClaimedAccounts
    }

    func transport(for credential: RelayClient.Credential) -> RelayTransport {
        Connection(relay: self, credential: credential)
    }

    func isConnected(_ account: UUID) -> Bool {
        connections[RoutingID.of(accountUUID: account)] != nil
    }

    /// Connections opened so far, refused ones included.
    private(set) var connectionAttempts = 0

    /// The network drops this account's connection.
    func drop(_ account: UUID) {
        connections[RoutingID.of(accountUUID: account)]?.dropped()
    }

    fileprivate func account(for credential: RelayClient.Credential) -> UUID? {
        switch credential {
        case .sessionToken(let token): return server.account(forToken: token)
        case .developmentAccount(let account): return acceptsClaimedAccounts ? account : nil
        }
    }

    fileprivate func attach(_ connection: Connection, as routingID: Data) {
        connections[routingID] = connection
    }

    fileprivate func detach(_ connection: Connection, as routingID: Data) {
        if connections[routingID] === connection { connections[routingID] = nil }
    }

    fileprivate func route(_ data: Data, from sender: Data) throws {
        let frame = try RelayFrame(decoding: data)
        guard frame.kind == .deliver else { return }
        if let receiver = connections[frame.peer] {
            receiver.onFrame?(try RelayFrame(kind: .deliver, peer: sender, body: frame.body).encoded())
        } else {
            connections[sender]?.onFrame?(try RelayFrame(kind: .peerUnavailable, peer: frame.peer).encoded())
        }
    }

    final class Connection: RelayTransport {
        private(set) var state: RelayClient.State = .disconnected {
            didSet { if state != oldValue { onStateChange?(state) } }
        }
        var onStateChange: ((RelayClient.State) -> Void)?
        var onFrame: ((Data) -> Void)?

        private weak var relay: InProcessRelay?
        private let credential: RelayClient.Credential
        private var routingID: Data?

        fileprivate init(relay: InProcessRelay, credential: RelayClient.Credential) {
            self.relay = relay
            self.credential = credential
        }

        func connect() {
            guard state == .disconnected else { return }
            state = .connecting
            // Opens a moment later, as a WebSocket does.
            Task { @MainActor [self] in
                guard state == .connecting, let relay else { return }
                relay.connectionAttempts += 1
                guard let account = relay.account(for: credential) else {
                    // Upgraded first, then closed "unauthorized".
                    state = .connected
                    state = .disconnected
                    return
                }
                let routingID = RoutingID.of(accountUUID: account)
                self.routingID = routingID
                relay.attach(self, as: routingID)
                state = .connected
            }
        }

        func disconnect() {
            if let routingID { relay?.detach(self, as: routingID) }
            routingID = nil
            state = .disconnected
        }

        func send(_ frames: [Data]) async throws {
            guard state == .connected, let relay, let routingID else { throw RelayClientError.notConnected }
            for frame in frames { try relay.route(frame, from: routingID) }
        }

        fileprivate func dropped() {
            disconnect()
        }
    }
}
