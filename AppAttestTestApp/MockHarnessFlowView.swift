//
//  MockHarnessFlowView.swift
//  AppAttestTestApp
//
//  Fake-data preview of the guided-sequence redesign — NOT wired to
//  AppAttestKit or any real Apple call. Purely for evaluating the UX before
//  committing to wiring it for real. HarnessView.swift / HarnessModel.swift
//  (the still-intact, working real harness) are untouched by this file.
//

import SwiftUI

struct MockHarnessFlowView: View {
    @State private var model = MockHarnessFlowModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    banner

                    VStack(spacing: 10) {
                        StepRow(
                            number: 1,
                            title: "Generate Identity Key",
                            subtitle: model.fakeIdentityPrefix.map { "public key: \($0)…" },
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

                    DisclosureGroup("Preview scenarios") {
                        VStack(alignment: .leading, spacing: 8) {
                            Button("Simulate a failure") { model.simulateFailure() }
                            Button("Reset module state", role: .destructive) { model.resetModuleState() }
                            Button("Delete identity key", role: .destructive) { model.deleteIdentityKey() }
                        }
                        .padding(.top, 8)
                    }
                    .padding(12)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                }
                .padding()
            }
            .navigationTitle("Attest Harness (Preview)")
        }
    }

    private var banner: some View {
        HStack {
            Text("state: \(model.stateLabel)")
                .font(.system(.footnote, design: .monospaced))
            Spacer()
            Text("MOCK — no real Apple calls")
                .font(.caption2.bold())
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.orange.opacity(0.2), in: Capsule())
                .foregroundStyle(.orange)
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
    MockHarnessFlowView()
}
