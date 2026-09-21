//
//  HarnessFlowView.swift
//  AppAttestTestApp
//
//  Real version of the guided-sequence UX, approved via
//  MockHarnessFlowView's fake-data preview. Wired to HarnessFlowModel —
//  real AttestationCoordinator, real DCAppAttestService calls, under the
//  development App Attest environment (safe for repeated real-device
//  testing). LocalFakeTransport still stands in for the Auth Server.
//

import SwiftUI

struct HarnessFlowView: View {
    @State private var model = HarnessFlowModel()

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
        .task { await model.restoreOnAppear() }
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
