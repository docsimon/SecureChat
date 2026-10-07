//
//  HarnessFlowView.swift
//  AppAttestTestApp
//
//  Real version of the guided-sequence UX, approved via
//  MockHarnessFlowView's fake-data preview. Wired to HarnessFlowModel —
//  real AttestationCoordinator, real DCAppAttestService calls, under the
//  development App Attest environment (safe for repeated real-device
//  testing). Which server it talks to (mock / local Docker / a custom URL)
//  is the "Backend" picker below — see TransportBackend.swift.
//

import SwiftUI

private enum BackendKind: String, CaseIterable, Identifiable, Hashable {
    case mock = "Mock"
    case localDocker = "Local Docker"
    case custom = "Custom"
    var id: String { rawValue }

    init(_ backend: TransportBackend) {
        switch backend {
        case .mock: self = .mock
        case .localDocker: self = .localDocker
        case .custom: self = .custom
        }
    }
}

struct HarnessFlowView: View {
    @State private var model = HarnessFlowModel()
    @State private var customURLText = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    banner

                    VStack(spacing: 10) {
                        StepRow(
                            number: 1,
                            title: "Generate Identity Key",
                            subtitle: model.identityPublicKeyPrefix.map { "public key: \($0)…" },
                            state: identityState,
                            action: { Task { await model.generateIdentity() } }
                        )
                        StepRow(
                            number: 2,
                            title: "Register (ensureAttested)",
                            subtitle: "The production flow: key → /challenge → Apple → /register. Resumes from the persisted state — tap again after a failure",
                            state: registerState,
                            action: { Task { await model.register() } }
                        )
                        StepRow(
                            number: 3,
                            title: "Sign Assertion",
                            subtitle: "Repeatable — every authenticated request does this",
                            state: signState,
                            isRepeatable: true,
                            action: { Task { await model.sign() } }
                        )
                    }

                    if let point = model.gate.pausedAt {
                        Button {
                            model.gate.release()
                        } label: {
                            HStack {
                                Image(systemName: "pause.circle.fill")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Paused \(point)").font(.headline)
                                    Text("Tap to continue — or force-quit / cut the network first")
                                        .font(.caption)
                                }
                                Spacer()
                                Image(systemName: "play.fill")
                            }
                            .padding(12)
                            .background(Color.orange.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }

                    stepControl

                    NavigationLink(destination: HarnessHistoryListView(sessions: model.sessions)) {
                        HStack {
                            Image(systemName: "clock")
                            Text("History")
                            Spacer()
                            Text("\(model.sessions.filter { !$0.events.isEmpty }.count) sessions")
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)

                    DisclosureGroup("Backend") {
                        VStack(alignment: .leading, spacing: 8) {
                            Picker("Backend", selection: backendKindBinding) {
                                ForEach(BackendKind.allCases) { kind in
                                    Text(kind.rawValue).tag(kind)
                                }
                            }
                            .pickerStyle(.segmented)

                            if BackendKind(model.transportBackend) == .custom {
                                TextField("https://host:port", text: $customURLText)
                                    .textFieldStyle(.roundedBorder)
                                    .keyboardType(.URL)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .onSubmit(applyCustomURL)
                            }

                            Text(model.transportBackend.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 8)
                    }
                    .padding(12)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))

                    DisclosureGroup("Danger zone") {
                        VStack(alignment: .leading, spacing: 8) {
                            Button("Reset module state", role: .destructive) {
                                Task { await model.resetModuleState() }
                            }
                            Button("Delete identity key", role: .destructive) {
                                Task { await model.deleteIdentityKey() }
                            }
                        }
                        .padding(.top, 8)
                    }
                    .padding(12)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                }
                .padding()
            }
            .navigationTitle("Attest Harness")
        }
        .task {
            await model.restoreOnAppear()
            if case .custom(let url) = model.transportBackend {
                customURLText = url.absoluteString
            }
        }
    }

    private var backendKindBinding: Binding<BackendKind> {
        Binding(
            get: { BackendKind(model.transportBackend) },
            set: { newKind in
                switch newKind {
                case .mock:
                    model.transportBackend = .mock
                case .localDocker:
                    model.transportBackend = .localDocker
                case .custom:
                    applyCustomURL()
                }
            })
    }

    /// Only actually switches the backend if `customURLText` is a valid URL
    /// — an empty or malformed field just leaves the picker on "Custom"
    /// without a live backend behind it yet, rather than crashing or
    /// silently falling back to a different one.
    private func applyCustomURL() {
        guard let url = URL(string: customURLText), !customURLText.isEmpty else { return }
        model.transportBackend = .custom(url)
    }

    /// Per-endpoint pause / failure injection — see ControllableTransport.swift.
    /// Read by the transport when the coordinator calls the endpoint, so set
    /// it BEFORE tapping Register (or mid-backoff, for the next retry).
    private var stepControl: some View {
        @Bindable var gate = model.gate
        return DisclosureGroup("Step control") {
            VStack(alignment: .leading, spacing: 8) {
                // Outside a Form a menu Picker hides its own label, so the
                // endpoint name is drawn explicitly next to it.
                HStack {
                    Text("GET /challenge")
                        .font(.system(.subheadline, design: .monospaced).bold())
                    Spacer()
                    Picker("GET /challenge", selection: $gate.challengeBehavior) {
                        ForEach(EndpointBehavior.challengeOptions) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden()
                }
                Text("Your Auth Server issues the 32 random bytes Apple will sign over. Called after the App Attest key exists, before Apple is contacted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Divider()
                HStack {
                    Text("POST /register")
                        .font(.system(.subheadline, design: .monospaced).bold())
                    Spacer()
                    Picker("POST /register", selection: $gate.registerBehavior) {
                        ForEach(EndpointBehavior.registerOptions) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden()
                }
                Text("Sends Apple's attestation to your Auth Server, which verifies it and returns the account UUID. Called after Apple has answered.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Divider()
                Text("Applies to the next call of that endpoint and stays until changed. Resets to pass-through on relaunch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }

    private var banner: some View {
        HStack {
            Text("state: \(model.stateLabel)")
                .font(.system(.footnote, design: .monospaced))
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(environmentBadge.text)
                    .font(.caption2.bold())
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(environmentBadge.color.opacity(0.2), in: Capsule())
                    .foregroundStyle(environmentBadge.color)
                Text("\(model.realAttemptCount) keys generated (local)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(model.appleAttestationCount) Apple attestations")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// From the aaguid in Apple's own attestation response, never from the
    /// entitlement — see `HarnessFlowModel.attestationEnvironment`. Grey means
    /// "no evidence", which is not the same as "development".
    private var environmentBadge: (text: String, color: Color) {
        switch model.attestationEnvironment {
        case .development: return ("APPLE: DEVELOPMENT", .green)
        case .production: return ("APPLE: PRODUCTION", .red)
        case .unrecognised: return ("APPLE: UNRECOGNISED AAGUID", .orange)
        case nil:
            return (model.attested ? "ENVIRONMENT NOT RECORDED" : "NO ATTESTATION YET", .secondary)
        }
    }

    private var identityState: StepRow.State {
        if model.activeStep == .identity { return .inProgress }
        return model.identityGenerated ? .done : .available
    }

    private var registerState: StepRow.State {
        if model.activeStep == .register { return .inProgress }
        if !model.identityGenerated { return .locked }
        return model.attested ? .done : .available
    }

    private var signState: StepRow.State {
        if model.activeStep == .sign { return .inProgress }
        return model.attested ? .done : .locked
    }
}

#Preview {
    HarnessFlowView()
}
