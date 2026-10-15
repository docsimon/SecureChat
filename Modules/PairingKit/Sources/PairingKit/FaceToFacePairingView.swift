//
//  FaceToFacePairingView.swift
//  PairingKit
//
//  THE pairing screen (Architecture/pairing-workflow.md, "One screen"),
//  shown by SecureChat and by the PairingTestApp and SessionTestApp
//  harnesses alike, so every change to how pairing looks and feels is
//  tried on the bench and the phones exactly as it will ship.
//
//  MVP (2026-10-15): one line of instructions, the QR code as large as the
//  screen allows, one status line. The front camera reads unseen. Nothing
//  times out and nothing moves on by itself: the screen stays until the
//  person closes it, so if only one phone has read the other, holding them
//  together a little longer completes the other.
//
//  Nobody sees their own screen in this position, so progress is felt: a
//  tap when their code is read, the full vibration and a sound when both
//  phones have each other's key, an error buzz for a refused code.
//
//  The rules of the attempt are `FaceToFacePairing`'s. Hosts add what is
//  their own: which scans count (`scan`), what a scanner failure is logged
//  as, and Debug-only lines for the debug sheet. Presenting and dismissing
//  is the host's.
//

import SwiftUI
import AudioToolbox
import UIKit

public struct FaceToFacePairingView<Debug: View>: View {

    /// What reads the codes. Previews have no camera, and asking for one
    /// there would only fail.
    enum CameraFeed {
        case live
        case none
    }

    @ObservedObject private var pairing: FaceToFacePairing
    private let errorCorrection: PairingQRCode.ErrorCorrection
    private let scan: @MainActor (String) -> FaceToFacePairing.Event?
    private let signal: @MainActor (PairingFeedback) -> Void
    private let onScannerFailure: @MainActor (QRCodeScannerView.Failure) -> Void
    private let cameraFeed: CameraFeed
    private let debug: Debug

    /// Why the camera is not reading, when it is not. The code stays up:
    /// the other phone can read this one regardless.
    @State private var scannerProblem: QRCodeScannerView.Failure?
    @State private var previousBrightness: CGFloat?
    @State private var showingDebug = false

    /// - Parameters:
    ///   - scan: what a code read by the camera does. Defaults to
    ///     `pairing.scanned`; a host wraps it to log, or returns nil when
    ///     the result must not be signalled (the contact could not be saved).
    ///   - signal: how progress is felt and heard. `PairingSignal.live` on
    ///     phones; previews and tests pass their own.
    ///   - onScannerFailure: for the host's log. The screen shows the
    ///     problem itself.
    ///   - debug: shown in the debug sheet, Debug builds only.
    public init(pairing: FaceToFacePairing,
                errorCorrection: PairingQRCode.ErrorCorrection = .medium,
                scan: (@MainActor (String) -> FaceToFacePairing.Event?)? = nil,
                signal: @escaping @MainActor (PairingFeedback) -> Void = PairingSignal.live,
                onScannerFailure: @escaping @MainActor (QRCodeScannerView.Failure) -> Void = { _ in },
                @ViewBuilder debug: () -> Debug) {
        self.init(pairing: pairing, errorCorrection: errorCorrection, scan: scan, signal: signal,
                  onScannerFailure: onScannerFailure, cameraFeed: .live, scannerProblem: nil, debug: debug)
    }

    /// Everything public plus what previews set: no camera, and a camera
    /// problem to start with.
    init(pairing: FaceToFacePairing,
         errorCorrection: PairingQRCode.ErrorCorrection = .medium,
         scan: (@MainActor (String) -> FaceToFacePairing.Event?)? = nil,
         signal: @escaping @MainActor (PairingFeedback) -> Void = PairingSignal.live,
         onScannerFailure: @escaping @MainActor (QRCodeScannerView.Failure) -> Void = { _ in },
         cameraFeed: CameraFeed,
         scannerProblem: QRCodeScannerView.Failure?,
         @ViewBuilder debug: () -> Debug) {
        self.pairing = pairing
        self.errorCorrection = errorCorrection
        self.scan = scan ?? { [pairing] in pairing.scanned($0) }
        self.signal = signal
        self.onScannerFailure = onScannerFailure
        self.cameraFeed = cameraFeed
        self.debug = debug()
        _scannerProblem = State(initialValue: scannerProblem)
    }

    public var body: some View {
        VStack(spacing: 16) {
            Text("Hold the phones screen to screen until you feel a long vibration.")
                .font(.headline)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.5)

            // The QR code takes the space first: at large text sizes the
            // words shrink, not the code the other camera has to read.
            if let code = pairing.codeToShow,
               let image = PairingQRCode.image(for: code, errorCorrection: errorCorrection) {
                Image(decorative: image, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel("Your pairing code")
                    .layoutPriority(1)
            }

            status

            scanner

#if DEBUG
            Button("Debug") { showingDebug = true }
                .font(.footnote)
#endif
        }
        .padding()
        .frame(maxHeight: .infinity)
        // White whatever the appearance: the screen is a light source for
        // the other camera.
        .foregroundStyle(.black)
        .background(Color.white.ignoresSafeArea())
        .environment(\.colorScheme, .light)
        .onAppear(perform: begin)
        .onDisappear(perform: end)
#if DEBUG
        .sheet(isPresented: $showingDebug) {
            PairingDebugSheet(pairing: pairing, use: handle) { debug }
        }
#endif
    }

    private var status: some View {
        Group {
            switch (scannerProblem, pairing.progress) {
            case (_, .bothWays(let contact)):
                Label("Paired with \(contact.displayName)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case (_, .readTheirs(let contact)):
                Label("Got \(contact.displayName). Keep holding…", systemImage: "arrow.left.arrow.right")
                    .foregroundStyle(.orange)
            case (_, .refused(let error)):
                Label(PairingSignal.message(for: error), systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
            case (.accessDenied?, .looking):
                VStack(spacing: 4) {
                    Text("SecureChat needs the camera to read the other phone's code.")
                    Button("Allow camera") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            case (.cameraUnavailable?, .looking):
                Label("No camera here. The other phone can still read this code.", systemImage: "camera.slash")
                    .foregroundStyle(.secondary)
            case (nil, .looking):
                Text("Looking for the other phone…").foregroundStyle(.secondary)
            }
        }
        .font(.headline)
        .multilineTextAlignment(.center)
        .lineLimit(3)
        .minimumScaleFactor(0.5)
    }

    /// Reads unseen: with the phones face to face nobody can look at a
    /// preview anyway (iOS still shows its camera dot).
    @ViewBuilder
    private var scanner: some View {
        if cameraFeed == .live, scannerProblem == nil {
            QRCodeScannerView(camera: .front, onCode: handle, onFailure: { failure in
                scannerProblem = failure
                onScannerFailure(failure)
            })
            .frame(width: 1, height: 1)
            .opacity(0)
            .accessibilityHidden(true)
        }
    }

    private func handle(_ code: String) {
        guard let event = scan(code) else { return }
        switch event {
        case .readTheirs: signal(.readTheirs)
        case .completed: signal(.completed)
        case .refused: signal(.failed)
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

extension FaceToFacePairingView where Debug == EmptyView {
    public init(pairing: FaceToFacePairing,
                errorCorrection: PairingQRCode.ErrorCorrection = .medium,
                scan: (@MainActor (String) -> FaceToFacePairing.Event?)? = nil,
                signal: @escaping @MainActor (PairingFeedback) -> Void = PairingSignal.live,
                onScannerFailure: @escaping @MainActor (QRCodeScannerView.Failure) -> Void = { _ in }) {
        self.init(pairing: pairing, errorCorrection: errorCorrection, scan: scan, signal: signal,
                  onScannerFailure: onScannerFailure, debug: { EmptyView() })
    }
}

/// What the person holding the phone should feel or hear.
public enum PairingFeedback: Equatable, Sendable {
    /// Their code was read.
    case readTheirs
    /// Both phones have each other's key.
    case completed
    /// A refused code.
    case failed
}

/// How pairing is felt, heard and worded.
public enum PairingSignal {

    /// The full vibration is what was confirmed on phones (2026-10-13);
    /// `UIFeedbackGenerator` alone could not be felt.
    @MainActor
    public static func live(_ feedback: PairingFeedback) {
        switch feedback {
        case .readTheirs:
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case .completed:
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            AudioServicesPlaySystemSound(1016)
        case .failed:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    /// For the person holding the phone; the cause in detail is the
    /// host's to log.
    public static func message(for error: PairingError) -> String {
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
}
