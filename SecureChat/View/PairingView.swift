//
//  PairingView.swift
//  SecureChat
//
//  "Add contact": hold the two phones face to face.
//

import SwiftUI
import PairingKit

struct PairingView: View {

    @Bindable var viewModel: PairingViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.phase {
                case .needsName:
                    nameStep
                case .pairing(let pairing):
                    PairingSessionView(pairing: pairing, viewModel: viewModel)
                case .unavailable(let message):
                    ContentUnavailableView("Can't add a contact", systemImage: "exclamationmark.triangle",
                                           description: Text(message))
                }
            }
            .navigationTitle("Add contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var nameStep: some View {
        Form {
            Section {
                TextField("Your name", text: $viewModel.draftName)
                    .textContentType(.name)
                    .autocorrectionDisabled()
                    .submitLabel(.continue)
                    .onSubmit { viewModel.confirmName() }
            } footer: {
                Text("Shown to the people you pair with. They can change what they call you on their own phone.")
            }
            Button("Continue") { viewModel.confirmName() }
                .disabled(!viewModel.canConfirmName)
        }
    }
}

private struct PairingSessionView: View {

    @ObservedObject var pairing: FaceToFacePairing
    @Bindable var viewModel: PairingViewModel

    @State private var previousBrightness: CGFloat?
#if DEBUG && targetEnvironment(simulator)
    @State private var pastedCode = ""
#endif

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text("Hold your phones face to face")
                    .font(.title3.bold())
                Text("Both open on this screen, a hand's width apart. You'll feel a vibration when it's done.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Stays up after this phone is done: the other one may still
            // need to read it.
            if let code = pairing.codeToShow, let image = PairingQRCode.image(for: code) {
                Image(decorative: image, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .padding(12)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel("Your pairing code")
            }

            status

            Spacer(minLength: 0)

            HStack(alignment: .center, spacing: 16) {
                scanner
                    .frame(width: 84, height: 112)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 6) {
                    Picker("Camera", selection: $viewModel.camera) {
                        Text("Front").tag(QRCodeScannerView.Camera.front)
                        Text("Rear").tag(QRCodeScannerView.Camera.back)
                    }
                    .pickerStyle(.segmented)
                    Text("Not reading? Switch to the rear camera and point it at their screen.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

#if DEBUG && targetEnvironment(simulator)
            // The Simulator has no camera: paste a code copied from the
            // PairingTestApp harness.
            HStack {
                TextField("Paste a code (Simulator)", text: $pastedCode)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Use") {
                    viewModel.scanned(pastedCode)
                    pastedCode = ""
                }
                .disabled(pastedCode.isEmpty)
            }
            .font(.footnote)
#endif
        }
        .padding()
        .onChange(of: viewModel.camera) { viewModel.cameraChanged() }
        .onAppear(perform: begin)
        .onDisappear(perform: end)
    }

    @ViewBuilder
    private var scanner: some View {
        switch viewModel.scannerProblem {
        case .none:
            QRCodeScannerView(camera: viewModel.camera,
                              onCode: { viewModel.scanned($0) },
                              onFailure: { viewModel.scannerFailed($0) })
        case .accessDenied:
            Button("Allow camera") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.footnote)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.quaternary)
        case .cameraUnavailable:
            Image(systemName: "camera.slash")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.quaternary)
        }
    }

    private var status: some View {
        Group {
            switch pairing.progress {
            case .looking:
                if viewModel.scannerProblem == .accessDenied {
                    Text("SecureChat needs the camera to read the other phone's code.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Looking for the other phone…").foregroundStyle(.secondary)
                }
            case .readTheirs(let contact):
                Label("Found \(contact.displayName). Keep the phones together…", systemImage: "arrow.left.arrow.right")
                    .foregroundStyle(.orange)
            case .bothWays(let contact):
                Label("Paired with \(contact.displayName)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .refused(let error):
                Label(Self.message(for: error), systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
            }
        }
        .font(.headline)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, minHeight: 44)
    }

    private static func message(for error: PairingError) -> String {
        switch error {
        case .notAPairingCode, .malformed, .invalidIdentityKey, .invalidDisplayName:
            return "That isn't a SecureChat pairing code."
        case .unsupportedVersion:
            return "That code is from a newer version of SecureChat. Update the app and try again."
        case .ownCode:
            return "That's your own code."
        case .conflictsWithExistingContact:
            return "That code doesn't match the contact you already have for this person."
        }
    }

    // MARK: Screen

    private var screen: UIScreen? {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen }.first
    }

    /// Full brightness and no auto-lock while the code is being shown.
    private func begin() {
        previousBrightness = screen?.brightness
        screen?.brightness = 1
        UIApplication.shared.isIdleTimerDisabled = true
    }

    private func end() {
        if let previousBrightness { screen?.brightness = previousBrightness }
        UIApplication.shared.isIdleTimerDisabled = false
    }
}
