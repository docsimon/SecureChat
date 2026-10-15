//
//  PairingCodeScreen.swift
//  PairingKit
//
//  Pairing, screen 2: only the QR code, as large as the screen allows, at
//  full brightness, while the camera reads the other phone. White whatever
//  the appearance: the screen is a light source for the other camera.
//
//  With the front camera nobody needs to see the preview, so it is not
//  shown (iOS still shows its camera dot). With the rear camera a small
//  viewfinder appears, to aim with.
//

import SwiftUI
import UIKit

struct PairingCodeScreen: View {

    /// What fills the camera window. Previews have no camera, and asking
    /// for one there would only fail.
    enum CameraFeed {
        case live
        /// A still placeholder, for previews.
        case still
    }

    let code: String?
    let errorCorrection: PairingQRCode.ErrorCorrection
    @Binding var camera: QRCodeScannerView.Camera
    let scannerProblem: QRCodeScannerView.Failure?
    let cameraFeed: CameraFeed
    let onCode: @MainActor (String) -> Void
    let onScannerFailure: @MainActor (QRCodeScannerView.Failure) -> Void
    let done: () -> Void
    /// Debug builds only.
    let showDebug: (() -> Void)?

    @State private var previousBrightness: CGFloat?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Done", action: done)
                Spacer()
                if let showDebug {
                    Button("Debug", action: showDebug).font(.footnote)
                }
            }
            .padding()

            Spacer(minLength: 0)

            if let code, let image = PairingQRCode.image(for: code, errorCorrection: errorCorrection) {
                Image(decorative: image, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .padding(16)
                    .accessibilityLabel("Your pairing code")
            }

            Spacer(minLength: 0)

            cameraControls
                .padding()
        }
        .foregroundStyle(.black)
        .tint(.blue)
        .background(Color.white.ignoresSafeArea())
        .environment(\.colorScheme, .light)
        .onAppear(perform: begin)
        .onDisappear(perform: end)
    }

    private var cameraControls: some View {
        VStack(spacing: 12) {
            switch scannerProblem {
            case .accessDenied:
                Button("Allow camera") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.footnote)
            case .cameraUnavailable:
                Label("No camera", systemImage: "camera.slash")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .none:
                scanner
            }
            Picker("Camera", selection: $camera) {
                Text("Front").tag(QRCodeScannerView.Camera.front)
                Text("Rear").tag(QRCodeScannerView.Camera.back)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 220)
        }
    }

    /// The front camera reads unseen; the rear one shows where it points.
    @ViewBuilder
    private var scanner: some View {
        let visible = camera == .back
        Group {
            switch cameraFeed {
            case .live:
                QRCodeScannerView(camera: camera, onCode: onCode, onFailure: onScannerFailure)
            case .still:
                Image(systemName: "camera.fill")
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.black)
            }
        }
        .frame(width: visible ? 120 : 1, height: visible ? 160 : 1)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .opacity(visible ? 1 : 0)
        .accessibilityHidden(!visible)
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
