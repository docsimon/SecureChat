//
//  PairingHarnessView.swift
//  PairingTestApp
//
//  A test bench, not the product's pairing screen: everything is on one page
//  and nothing is hidden.
//

import SwiftUI
import PairingKit

struct PairingHarnessView: View {

    @StateObject private var model = PairingHarnessModel()
    @State private var isScanning = false
    @State private var isFaceToFace = false
    @State private var pastedCode = ""

    var body: some View {
        NavigationStack {
            Form {
                identitySection
                myCodeSection
                scanSection
                contactsSection
                logSection
            }
            .navigationTitle("Pairing harness")
            .sheet(isPresented: $isScanning) { scannerSheet }
            .fullScreenCover(isPresented: $isFaceToFace) { FaceToFaceBenchView(model: model) }
        }
    }

    // MARK: Sections

    private var identitySection: some View {
        Section("This device (throwaway identity)") {
            TextField("Display name", text: $model.displayName)
                .autocorrectionDisabled()
            LabeledContent("Key", value: PairingHarnessModel.fingerprint(model.identityPublicKey) + " …")
            LabeledContent("Account", value: model.accountUUID.uuidString.prefix(8) + "…")
            Button("New identity") { model.newIdentity() }
        }
    }

    private var myCodeSection: some View {
        Section("My code") {
            if let code = model.myCode, let image = PairingQRCode.image(for: code) {
                Image(decorative: image, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .padding(12)
                    .background(.white)
                    .frame(maxWidth: 280)
                    .frame(maxWidth: .infinity)
                Button("Copy code as text") { UIPasteboard.general.string = code }
            } else {
                Text("Enter a display name to get a code.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var scanSection: some View {
        Section("Their code") {
            Button("Pair face to face (front camera)") { isFaceToFace = true }
                .disabled(model.myCode == nil)
            Button("Scan with the rear camera") { isScanning = true }
            TextField("…or paste a code", text: $pastedCode, axis: .vertical)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .lineLimit(1...3)
            Button("Use pasted code") {
                model.handle(scanned: pastedCode)
                pastedCode = ""
            }
            .disabled(pastedCode.isEmpty)
        }
    }

    private var contactsSection: some View {
        Section("Contacts (\(model.contacts.count))") {
            ForEach(model.contacts) { contact in
                VStack(alignment: .leading, spacing: 2) {
                    Text(contact.displayName)
                    Text("\(PairingHarnessModel.fingerprint(contact.identityPublicKey)) …  ·  \(contact.accountUUID.uuidString.prefix(8))…")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            if !model.contacts.isEmpty {
                Button("Remove all", role: .destructive) { model.removeAllContacts() }
            }
        }
    }

    private var logSection: some View {
        Section("Log") {
            ForEach(model.log) { entry in
                Text(entry.text)
                    .font(.callout)
                    .foregroundStyle(entry.isError ? .red : .primary)
            }
        }
    }

    private var scannerSheet: some View {
        NavigationStack {
            QRCodeScannerView(
                onCode: { code in
                    model.handle(scanned: code)
                    isScanning = false
                },
                onFailure: { failure in
                    model.scannerFailed(failure)
                    isScanning = false
                })
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("Scan their code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isScanning = false }
                }
            }
        }
    }
}
