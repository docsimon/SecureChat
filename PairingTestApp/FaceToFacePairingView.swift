//
//  FaceToFacePairingView.swift
//  PairingTestApp
//
//  Test bench for pairing with the phones held face to face. The rules of
//  the attempt are PairingKit's `FaceToFacePairing`, the code that ships;
//  this view only shows the code, runs the camera, and signals.
//
//  Nobody sees their own screen in this position, so progress is felt and
//  heard: a tap when the other code is read, a full vibration and a sound
//  when the pairing is complete both ways. Times go to the harness log.
//

import SwiftUI
import AudioToolbox
import PairingKit

struct FaceToFacePairingView: View {

    @ObservedObject private var model: PairingHarnessModel
    @StateObject private var pairing: FaceToFacePairing

    @Environment(\.dismiss) private var dismiss
    @State private var camera: QRCodeScannerView.Camera = .front
    @State private var lowCorrection = false
    @State private var openedAt = Date()
    /// When this attempt first read the other code.
    @State private var readAt: Date?
    @State private var previousBrightness: CGFloat?
    @State private var impact = UIImpactFeedbackGenerator(style: .heavy)
    @State private var notification = UINotificationFeedbackGenerator()

    init(model: PairingHarnessModel) {
        self.model = model
        _pairing = StateObject(wrappedValue: FaceToFacePairing(
            identityPublicKey: model.identityPublicKey,
            accountUUID: model.accountUUID,
            displayName: model.displayName,
            contacts: { model.contacts },
            store: { model.add($0) }))
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Button("Done") { dismiss() }
                Spacer()
                Picker("Camera", selection: $camera) {
                    Text("Front").tag(QRCodeScannerView.Camera.front)
                    Text("Rear").tag(QRCodeScannerView.Camera.back)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }

            if let code = pairing.codeToShow,
               let image = PairingQRCode.image(for: code, errorCorrection: lowCorrection ? .low : .medium) {
                Image(decorative: image, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
            }

            statusLine

            HStack(alignment: .bottom, spacing: 16) {
                QRCodeScannerView(camera: camera, onCode: handle, onFailure: { failure in
                    model.scannerFailed(failure)
                    dismiss()
                })
                .frame(width: 96, height: 128)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Bigger squares (less error correction)", isOn: $lowCorrection)
                        .font(.footnote)
                    Text("Hold the phones face to face, 15–30 cm apart. A tap: this phone has read the other. A full vibration: both have.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.white)
        .environment(\.colorScheme, .light)
        .onChange(of: camera) { _ in restart() }
        .onAppear(perform: begin)
        .onDisappear(perform: end)
    }

    private var statusLine: some View {
        Group {
            switch pairing.progress {
            case .looking:
                Text("Looking for the other phone's code…").foregroundStyle(.secondary)
            case .readTheirs(let contact):
                Label("Read \(contact.displayName). Waiting for them to read this phone…",
                      systemImage: "arrow.left.arrow.right")
                    .foregroundStyle(.orange)
            case .bothWays(let contact):
                Label("Paired with \(contact.displayName), both ways", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .refused(let error):
                Label("Refused: \(PairingHarnessModel.describe(error))", systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
            }
        }
        .font(.headline)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, minHeight: 28)
    }

    private func handle(_ code: String) {
        guard let event = pairing.scanned(code) else { return }
        // The only clock that starts at a known moment is the screen opening,
        // so the first figure includes however long it took to get the two
        // phones in front of each other. The second is the one that says
        // something about reading: the gap between the two reads.
        let now = Date()
        let sinceOpened = String(format: "%.1f s after this screen opened", now.timeIntervalSince(openedAt))
        let settings = "\(camera == .front ? "front" : "rear") camera, \(lowCorrection ? "low" : "medium") error correction on this screen"
        switch event {
        case .readTheirs:
            readAt = now
            model.note("Read their code \(sinceOpened) (\(settings))")
            impact.impactOccurred()
            impact.prepare()
        case .completed:
            if let readAt {
                model.note(String(format: "Paired both ways %.1f s after reading their code", now.timeIntervalSince(readAt)))
            } else {
                model.note("Paired both ways on the first read, \(sinceOpened) (\(settings))")
            }
            // The feedback generators alone could not be felt on 2026-10-13
            // (iPhone 16 Plus, iPhone X; cause not established). The full
            // vibration does not go through them.
            notification.notificationOccurred(.success)
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            AudioServicesPlaySystemSound(1016)
        case .refused(let error):
            model.noteRefusal(error)
            notification.notificationOccurred(.error)
        }
    }

    private func restart() {
        openedAt = Date()
        readAt = nil
        pairing.restart()
    }

    // MARK: Screen

    private var screen: UIScreen? {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen }.first
    }

    /// Full brightness and no auto-lock while the code is being shown.
    private func begin() {
        restart()
        impact.prepare()
        notification.prepare()
        previousBrightness = screen?.brightness
        screen?.brightness = 1
        UIApplication.shared.isIdleTimerDisabled = true
    }

    private func end() {
        if let previousBrightness { screen?.brightness = previousBrightness }
        UIApplication.shared.isIdleTimerDisabled = false
    }
}
