//
//  SessionHarnessView.swift
//  SessionTestApp
//

import SwiftUI
import PairingKit
import SessionKit

struct SessionHarnessView: View {
    @ObservedObject var model: SessionHarnessModel
    @State private var pastedCode = ""
    @State private var pairingFaceToFace = false

    var body: some View {
        NavigationStack {
            Form {
                Section("This harness") {
                    TextField("Name", text: $model.displayName)
                    LabeledContent("Key", value: model.fingerprint + " …")
                    LabeledContent("Account", value: model.accountUUID.uuidString.prefix(8) + "…")
                    Button("Copy my pairing code") { UIPasteboard.general.string = model.pairingCode }
                }

                Section {
                    Button("Pair face to face") { pairingFaceToFace = true }
                        .disabled(model.pairingCode.isEmpty)
                    TextField("Paste their pairing code", text: $pastedCode)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Add contact") {
                        model.addContact(code: pastedCode)
                        pastedCode = ""
                    }
                    .disabled(pastedCode.isEmpty)
                } header: {
                    Text("Add a contact")
                } footer: {
                    Text("Face to face: hold this phone and the other (SecureChat or this harness) screen to screen until both vibrate. Without cameras, copy the code on the other Simulator or phone and paste it here, on both sides. Simulators share the Mac's clipboard.")
                }

                Section("Relay") {
                    TextField("ws://…/relay", text: $model.relayURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    if let service = model.service {
                        RelayStatusRow(service: service, model: model)
                    } else {
                        Button("Connect") { model.connect() }
                    }
                }

                Section("Contacts (\(model.contacts.count))") {
                    ForEach(model.contacts) { contact in
                        NavigationLink(value: contact.accountUUID) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(contact.displayName)
                                Text("\(SessionHarnessModel.fingerprint(contact.identityPublicKey)) …  ·  \(contact.accountUUID.uuidString.prefix(8))…")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    if !model.contacts.isEmpty {
                        Button("Remove all", role: .destructive) { model.removeAllContacts() }
                    }
                }

                Section("Log") {
                    ForEach(model.log) { entry in
                        Text(entry.text)
                            .font(.caption)
                            .foregroundStyle(entry.isError ? .red : .primary)
                    }
                }
            }
            .navigationTitle("Sessions")
            .fullScreenCover(isPresented: $pairingFaceToFace) {
                FaceToFacePairingSheet(model: model)
            }
            .navigationDestination(for: UUID.self) { account in
                if let contact = model.contacts.first(where: { $0.accountUUID == account }) {
                    if let service = model.service {
                        HarnessChatView(model: model, service: service, contact: contact)
                    } else {
                        Text("Connect to the relay first.")
                    }
                }
            }
        }
    }
}

private struct RelayStatusRow: View {
    @ObservedObject var service: SessionService
    let model: SessionHarnessModel

    var body: some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label)
            Spacer()
            if service.relayState == .disconnected {
                Button("Connect") { model.connect() }
            } else {
                Button("Disconnect") { model.disconnect() }
            }
        }
    }

    private var label: String {
        switch service.relayState {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting…"
        case .connected: return "Connected"
        }
    }

    private var color: Color {
        switch service.relayState {
        case .disconnected: return .red
        case .connecting: return .orange
        case .connected: return .green
        }
    }
}

struct HarnessChatView: View {
    @ObservedObject var model: SessionHarnessModel
    @ObservedObject var service: SessionService
    let contact: PairedContact
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 0) {
            Label(service.established.contains(contact.accountUUID) ? "Session open" : "No session",
                  systemImage: service.established.contains(contact.accountUUID) ? "lock.fill" : "lock.open")
                .font(.footnote)
                .foregroundStyle(service.established.contains(contact.accountUUID) ? .green : .secondary)
                .padding(8)

            List(model.messages[contact.accountUUID] ?? []) { message in
                HStack {
                    if message.mine { Spacer() }
                    Text(message.text)
                        .padding(8)
                        .background(message.mine ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.15),
                                    in: RoundedRectangle(cornerRadius: 10))
                    if !message.mine { Spacer() }
                }
                .listRowSeparator(.hidden)
            }
            .listStyle(.plain)

            HStack {
                TextField("Message", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(send)
                Button("Send", action: send)
                    .disabled(draft.isEmpty)
            }
            .padding()
        }
        .navigationTitle(contact.displayName)
        .navigationBarTitleDisplayMode(.inline)
        // Opening the chat opens the session (session-workflow.md).
        .onAppear { model.open(contact) }
    }

    private func send() {
        guard !draft.isEmpty else { return }
        model.send(draft, to: contact)
        draft = ""
    }
}
