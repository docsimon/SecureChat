//
//  HarnessView.swift
//  AppAttestTestApp
//
//  Deliberately utilitarian — this is a debug tool, not a product screen.
//  See appattestkit-module-design.md §2: "no UI package... writing two
//  screens" applies here too; this one screen is all the harness needs.
//

import SwiftUI

struct HarnessView: View {
    @State private var model = HarnessModel()

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("state: \(model.state)")
                        .font(.system(.footnote, design: .monospaced))
                    Spacer()
                    Text("real attempts: \(model.realAttemptCount)")
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Text("Transport: local fake — no real server, no network (LocalFakeTransport.swift).")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button("Support") { model.checkSupport() }
                        Button("Restore") { Task { await model.restoreOnly() } }
                        Button("Attest") { Task { await model.runAttestation() } }
                            .buttonStyle(.borderedProminent)
                        Button("Sign") { Task { await model.signAssertion() } }
                    }
                    HStack {
                        Button("Reset module state", role: .destructive) {
                            Task { await model.resetModuleState() }
                        }
                        Button("Delete identity key", role: .destructive) {
                            model.deleteIdentityKey()
                        }
                    }
                }
                .buttonStyle(.bordered)
                .font(.footnote)

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

#Preview {
    HarnessView()
}
