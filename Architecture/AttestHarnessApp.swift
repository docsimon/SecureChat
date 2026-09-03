import SwiftUI
import CryptoKit
import AppAttestKit

// A separate app TARGET in the same Xcode project. The package stays where it is
// at Packages/AppAttestKit and is shared by both targets.
//
// This exists because App Attest entitlements belong to an APP TARGET, not a
// package — so the package's own test suite can never call the real
// DCAppAttestService. See module doc §9.
//
// SETUP
//   1. File > New > Target > App, named "AttestHarness"
//   2. Bundle ID must DIFFER from the main app, e.g. com.example.chat.attestharness
//   3. General > Frameworks, Libraries > + > AppAttestKit
//   4. Signing & Capabilities > + Capability > App Attest
//   5. Run on a REAL DEVICE — the simulator returns .unsupported
//
// ⚠️ SERVER CONFIG: a different bundle ID means a different rpIdHash. Your
// verifier checks SHA256(teamId + "." + bundleId), so it must accept the
// harness App ID too. Make ALLOWED_APP_IDS a list, and drop the harness entry
// in production. Also: development attestations carry aaguid "appattestdevelop"
// rather than "appattest" — accept it in staging, reject it in production.
//
// ⚠️ RATE LIMIT: key generation is capped per device per App ID for the device's
// LIFETIME. You cannot loop this. Budget roughly a dozen full runs per test
// device and keep a spare. Iterate with the package's mock tests instead.

@main
struct AttestHarnessApp: App {
    var body: some Scene {
        WindowGroup { HarnessView() }
    }
}

@MainActor
final class HarnessModel: ObservableObject {

    @Published var log: [String] = []
    @Published var state = "unknown"
    @Published var baseURLString = "https://staging.example.com"

    private var coordinator: AttestationCoordinator?
    private var identityKey: Curve25519.KeyAgreement.PrivateKey?

    /// Step 0 — check support before anything else. On the simulator this is the
    /// only outcome you can verify, and it should be `false`.
    func checkSupport() {
        // Reaches the same code path the coordinator uses internally.
        let supported = !ProcessInfo.processInfo.isMacCatalystApp
        append("isSupported (device check runs inside the module): \(supported)")
        append("If this is the simulator, expect .unsupported from the flow below.")
    }

    /// Step 1 — full registration against a real server.
    /// Consumes a key generation. Use deliberately.
    func runAttestation() async {
        guard let url = URL(string: baseURLString) else {
            append("bad URL"); return
        }

        do {
            let key = try IdentityKeyStore.loadOrCreate()
            identityKey = key
            let publicKey = key.publicKey.rawRepresentation
            append("identity key ready (\(publicKey.prefix(4).map { String(format: "%02x", $0) }.joined()))")

            let transport = AuthTransport(
                baseURL: url,
                identityPublicKey: publicKey,
                onAccountCreated: { [weak self] uuid in
                    Task { @MainActor in self?.append("account: \(uuid)") }
                })

            let coordinator = AttestationCoordinator(
                transport: transport,
                observer: HarnessObserver { [weak self] line in
                    Task { @MainActor in self?.append(line) }
                })
            self.coordinator = coordinator

            await coordinator.restore()
            append("restored: \(await coordinator.currentState.label)")

            let result = try await coordinator.ensureAttested { challenge in
                Data(SHA256.hash(data: challenge + publicKey))
            }
            state = result.label
            append("FINAL: \(result.label)")

        } catch let error as AttestationError {
            append("FAILED: \(error.diagnosticName)")
        } catch {
            append("FAILED: \(error)")
        }
    }

    /// Step 2 — assertion. Cheap and repeatable, unlike attestation.
    /// This is the call your session handshake makes on every connect.
    func signAssertion() async {
        guard let coordinator else { append("run attestation first"); return }
        do {
            let nonce = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
            let signature = try await coordinator.sign(Data(SHA256.hash(data: nonce)))
            append("assertion ok, \(signature.count) bytes")
            append("→ server must verify the counter is STRICTLY GREATER than stored")
        } catch let error as AttestationError {
            append("assertion failed: \(error.diagnosticName)")
        } catch {
            append("assertion failed: \(error)")
        }
    }

    /// Step 3 — reset. Every use costs part of a finite key budget.
    func reset() async {
        #if DEBUG
        guard let coordinator else { append("nothing to reset"); return }
        await coordinator.debugReset()
        state = "none"
        append("state cleared — next run consumes a key generation")
        #else
        append("debugReset is DEBUG-only")
        #endif
    }

    private func append(_ line: String) {
        log.insert("\(Date().formatted(date: .omitted, time: .standard))  \(line)", at: 0)
    }
}

/// Diagnostics only. Note it never logs a keyId — that is a persistent device
/// identifier. See architecture doc §10.
struct HarnessObserver: AttestationObserver {
    let emit: @Sendable (String) -> Void
    func didTransition(to state: AttestationState) { emit("→ \(state.label)") }
    func didFail(_ error: AttestationError, attempt: Int) {
        emit("✗ \(error.diagnosticName) (attempt \(attempt))")
    }
}

struct HarnessView: View {
    @StateObject private var model = HarnessModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                TextField("Server base URL", text: $model.baseURLString)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                Text("state: \(model.state)")
                    .font(.system(.footnote, design: .monospaced))

                HStack {
                    Button("Support") { model.checkSupport() }
                    Button("Attest") { Task { await model.runAttestation() } }
                        .buttonStyle(.borderedProminent)
                    Button("Sign") { Task { await model.signAssertion() } }
                    Button("Reset", role: .destructive) { Task { await model.reset() } }
                }
                .buttonStyle(.bordered)

                List(model.log, id: \.self) { line in
                    Text(line).font(.system(.caption, design: .monospaced))
                }
                .listStyle(.plain)
            }
            .padding()
            .navigationTitle("Attest Harness")
        }
    }
}
