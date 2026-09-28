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
                            title: "Attest",
                            subtitle: "Attests with Apple, then registers with the Auth Server",
                            state: attestState,
                            action: { Task { await model.attest() } }
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

    private var banner: some View {
        HStack {
            Text("state: \(model.stateLabel)")
                .font(.system(.footnote, design: .monospaced))
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("DEV SANDBOX")
                    .font(.caption2.bold())
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.green.opacity(0.2), in: Capsule())
                    .foregroundStyle(.green)
                Text("\(model.realAttemptCount) real attempts")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var identityState: StepRow.State {
        if model.activeStep == .identity { return .inProgress }
        return model.identityGenerated ? .done : .available
    }

    private var attestState: StepRow.State {
        if model.activeStep == .attest { return .inProgress }
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
