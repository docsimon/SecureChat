//
//  FaceToFacePairingView.swift
//  PairingTestApp
//
//  PROTOTYPE, to answer one question on two real phones: held face to face,
//  can each front camera read the code on the other screen, and how fast?
//  The screen shows this device's code and scans at the same time. With the
//  phones facing each other nobody sees their own screen, so the result is
//  a vibration and a sound; the time to read goes to the harness log.
//

import SwiftUI
import AudioToolbox
import PairingKit

struct FaceToFacePairingView: View {

    let model: PairingHarnessModel

    @Environment(\.dismiss) private var dismiss
    @State private var camera: QRCodeScannerView.Camera = .front
    @State private var lowCorrection = false
    @State private var result: PairingHarnessModel.ScanResult?
    /// The code is in view continuously; act on each distinct one once.
    @State private var handledCodes: Set<String> = []
    @State private var openedAt = Date()
    @State private var previousBrightness: CGFloat?

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

            if let code = model.myCode,
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
                    Text("Hold the phones face to face, 15–30 cm apart. A vibration means this phone has read the other.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.white)
        .environment(\.colorScheme, .light)
        .onChange(of: camera) { restartTimer() }
        .onAppear(perform: begin)
        .onDisappear(perform: end)
    }

    private var statusLine: some View {
        Group {
            switch result {
            case .none:
                Text("Looking for the other phone's code…").foregroundStyle(.secondary)
            case .added(let name):
                Label("Added \(name)", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .alreadyPaired(let name):
                Label("Already paired with \(name)", systemImage: "checkmark.circle").foregroundStyle(.green)
            case .refused(let reason):
                Label("Refused: \(reason)", systemImage: "xmark.octagon.fill").foregroundStyle(.red)
            }
        }
        .font(.headline)
        .frame(maxWidth: .infinity, minHeight: 28)
    }

    private func handle(_ code: String) {
        guard handledCodes.insert(code).inserted else { return }
        let elapsed = Date().timeIntervalSince(openedAt)
        let outcome = model.handle(scanned: code)
        result = outcome
        model.note(String(format: "Read in %.1f s with the %@ camera, %@ error correction on this screen",
                          elapsed, camera == .front ? "front" : "rear", lowCorrection ? "low" : "medium"))

        let feedback = UINotificationFeedbackGenerator()
        if case .refused = outcome {
            feedback.notificationOccurred(.error)
        } else {
            feedback.notificationOccurred(.success)
            AudioServicesPlaySystemSound(1057)
        }
    }

    private func restartTimer() {
        openedAt = Date()
        handledCodes = []
        result = nil
    }

    // MARK: Screen

    private var screen: UIScreen? {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen }.first
    }

    /// Full brightness and no auto-lock while the code is being shown.
    private func begin() {
        restartTimer()
        previousBrightness = screen?.brightness
        screen?.brightness = 1
        UIApplication.shared.isIdleTimerDisabled = true
    }

    private func end() {
        if let previousBrightness { screen?.brightness = previousBrightness }
        UIApplication.shared.isIdleTimerDisabled = false
    }
}
