//
//  FaceToFacePairingView.swift
//  PairingKit
//
//  THE pairing screens (Architecture/pairing-workflow.md, "Two screens"),
//  shown by SecureChat and by the PairingTestApp and SessionTestApp
//  harnesses alike, so every change to how pairing looks and feels is
//  tried on the bench and the phones exactly as it will ship.
//
//  1. Start: what to do, how the last attempt ended, and "Pair". Any text
//     size: it scrolls.
//  2. Code: only the QR code, as large as the screen allows, while the
//     camera reads the other phone. Nobody sees their own screen in this
//     position, so progress is felt: a tap when their code is read, the
//     full vibration when both phones have each other's key, an error
//     buzz when it fails.
//
//  On completion the code stays up for `holdAfterCompletion`, and the
//  vibration waits `completionSignalDelay`: the phone that completes first
//  keeps showing the code the other one needs, and nobody pulls away
//  before it has been read.
//
//  The rules of the attempt are `FaceToFacePairing`'s. Hosts add what is
//  their own: which scans count (`scan`), what a scanner failure is logged
//  as, and Debug-only content for the debug sheet. Presenting and
//  dismissing the whole thing is the host's.
//

import SwiftUI
import AudioToolbox
import UIKit

public struct FaceToFacePairingView<Debug: View>: View {

    @ObservedObject private var pairing: FaceToFacePairing
    private let errorCorrection: PairingQRCode.ErrorCorrection
    private let scan: @MainActor (String) -> FaceToFacePairing.Event?
    private let signal: @MainActor (PairingFeedback) -> Void
    private let onCameraChange: @MainActor (QRCodeScannerView.Camera) -> Void
    private let onScannerFailure: @MainActor (QRCodeScannerView.Failure) -> Void
    private let timing: PairingTiming
    private let cameraFeed: PairingCodeScreen.CameraFeed
    private let debug: Debug

    enum Screen: Equatable {
        case start
        case code
    }

    @State private var screen: Screen
    @State private var outcome: PairingOutcome?
    @State private var camera: QRCodeScannerView.Camera = .front
    @State private var scannerProblem: QRCodeScannerView.Failure?
    /// The last code refused during this attempt, for the start screen.
    @State private var lastRefusal: PairingError?
    @State private var showingDebug = false

    /// - Parameters:
    ///   - scan: what a code read by the camera does. Defaults to
    ///     `pairing.scanned`; a host wraps it to log, or returns nil when
    ///     the result must not be signalled (the contact could not be saved).
    ///   - signal: how progress is felt and heard. `PairingSignal.live` on
    ///     phones; previews and tests pass their own.
    ///   - onCameraChange: after the attempt restarted on the other camera.
    ///   - onScannerFailure: for the host's log. The screens show the
    ///     problem themselves.
    ///   - debug: shown in the debug sheet, Debug builds only.
    public init(pairing: FaceToFacePairing,
                errorCorrection: PairingQRCode.ErrorCorrection = .medium,
                scan: (@MainActor (String) -> FaceToFacePairing.Event?)? = nil,
                signal: @escaping @MainActor (PairingFeedback) -> Void = PairingSignal.live,
                onCameraChange: @escaping @MainActor (QRCodeScannerView.Camera) -> Void = { _ in },
                onScannerFailure: @escaping @MainActor (QRCodeScannerView.Failure) -> Void = { _ in },
                timing: PairingTiming = .standard,
                @ViewBuilder debug: () -> Debug) {
        self.init(pairing: pairing, errorCorrection: errorCorrection, scan: scan, signal: signal,
                  onCameraChange: onCameraChange, onScannerFailure: onScannerFailure, timing: timing,
                  screen: .start, outcome: nil, cameraFeed: .live, scannerProblem: nil, debug: debug)
    }

    /// Everything public plus where previews start: a screen, an outcome,
    /// a still camera window and a camera problem.
    init(pairing: FaceToFacePairing,
         errorCorrection: PairingQRCode.ErrorCorrection = .medium,
         scan: (@MainActor (String) -> FaceToFacePairing.Event?)? = nil,
         signal: @escaping @MainActor (PairingFeedback) -> Void = PairingSignal.live,
         onCameraChange: @escaping @MainActor (QRCodeScannerView.Camera) -> Void = { _ in },
         onScannerFailure: @escaping @MainActor (QRCodeScannerView.Failure) -> Void = { _ in },
         timing: PairingTiming = .standard,
         screen: Screen,
         outcome: PairingOutcome?,
         cameraFeed: PairingCodeScreen.CameraFeed,
         scannerProblem: QRCodeScannerView.Failure?,
         @ViewBuilder debug: () -> Debug) {
        self.pairing = pairing
        self.errorCorrection = errorCorrection
        self.scan = scan ?? { [pairing] in pairing.scanned($0) }
        self.signal = signal
        self.onCameraChange = onCameraChange
        self.onScannerFailure = onScannerFailure
        self.timing = timing
        self.cameraFeed = cameraFeed
        self.debug = debug()
        _screen = State(initialValue: screen)
        _outcome = State(initialValue: outcome)
        _scannerProblem = State(initialValue: scannerProblem)
    }

    public var body: some View {
        Group {
            switch screen {
            case .start:
                PairingStartScreen(outcome: outcome, cameraDenied: scannerProblem == .accessDenied,
                                   canPair: pairing.codeToShow != nil, pair: start, showDebug: showDebug)
            case .code:
                PairingCodeScreen(code: pairing.codeToShow, errorCorrection: errorCorrection,
                                  camera: $camera, scannerProblem: scannerProblem, cameraFeed: cameraFeed,
                                  onCode: handle, onScannerFailure: scannerFailed,
                                  done: leaveCodeScreen, showDebug: showDebug)
                    .toolbar(.hidden, for: .navigationBar)
            }
        }
        // Follows the attempt while the code is up: the completion signal
        // and hold, the timeout, and giving up when nothing is read.
        .task(id: FollowKey(screen: screen, progress: pairing.progress)) { await follow() }
        .onChange(of: camera) { camera in
            scannerProblem = nil
            lastRefusal = nil
            pairing.restart()
            onCameraChange(camera)
        }
#if DEBUG
        .sheet(isPresented: $showingDebug) {
            PairingDebugSheet(pairing: pairing, use: handle) { debug }
        }
#endif
    }

    private var showDebug: (() -> Void)? {
#if DEBUG
        return { showingDebug = true }
#else
        return nil
#endif
    }

    // MARK: Attempt

    private func start() {
        outcome = nil
        lastRefusal = nil
        pairing.restart()
        screen = .code
    }

    private func handle(_ code: String) {
        // A code pasted in the debug sheet from the start screen starts
        // an attempt, as tapping Pair would.
        if screen == .start { start() }
        guard let event = scan(code) else { return }
        switch event {
        case .readTheirs:
            signal(.readTheirs)
        case .refused(let error):
            lastRefusal = error
            signal(.failed)
        case .completed:
            // Signalled by `follow`, after the delay.
            break
        }
    }

    private func scannerFailed(_ failure: QRCodeScannerView.Failure) {
        scannerProblem = failure
        onScannerFailure(failure)
    }

    private func leaveCodeScreen() {
        if case .bothWays(let contact) = pairing.progress {
            finish(.paired(contact.displayName))
        } else {
            // Cancelled: nothing was saved, nothing to report.
            finish(nil)
        }
    }

    private func finish(_ outcome: PairingOutcome?) {
        self.outcome = outcome
        screen = .start
        pairing.restart()
    }

    private struct FollowKey: Equatable {
        let screen: Screen
        let progress: FaceToFacePairing.Progress
    }

    private func follow() async {
        guard screen == .code else { return }
        switch pairing.progress {
        case .looking, .refused:
            // Nothing read: the other phone may have given up already, and
            // nothing tells this one. Stop, and say so in a way that is felt.
            guard await wait(timing.idleLimit) else { return }
            signal(.failed)
            finish(lastRefusal.map(PairingOutcome.refused) ?? .nothingRead)
        case .readTheirs:
            // FaceToFacePairing times this out itself.
            break
        case .bothWays(let contact):
            guard await wait(timing.completionSignalDelay) else { return }
            signal(.completed)
            guard await wait(max(0, timing.holdAfterCompletion - timing.completionSignalDelay)) else { return }
            finish(.paired(contact.displayName))
        case .timedOut(let contact):
            signal(.failed)
            finish(.timedOut(contact.displayName))
        }
    }

    /// False when cancelled: the attempt moved on, or the screen went away.
    private func wait(_ seconds: TimeInterval) async -> Bool {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        return !Task.isCancelled
    }
}

extension FaceToFacePairingView where Debug == EmptyView {
    public init(pairing: FaceToFacePairing,
                errorCorrection: PairingQRCode.ErrorCorrection = .medium,
                scan: (@MainActor (String) -> FaceToFacePairing.Event?)? = nil,
                signal: @escaping @MainActor (PairingFeedback) -> Void = PairingSignal.live,
                onCameraChange: @escaping @MainActor (QRCodeScannerView.Camera) -> Void = { _ in },
                onScannerFailure: @escaping @MainActor (QRCodeScannerView.Failure) -> Void = { _ in },
                timing: PairingTiming = .standard) {
        self.init(pairing: pairing, errorCorrection: errorCorrection, scan: scan, signal: signal,
                  onCameraChange: onCameraChange, onScannerFailure: onScannerFailure, timing: timing,
                  debug: { EmptyView() })
    }
}

/// How the last attempt ended, for the start screen.
enum PairingOutcome: Equatable {
    case paired(String)
    /// Their code was read but they did not confirm in time. Nothing saved.
    case timedOut(String)
    /// The code screen was up for `idleLimit` without reading anything.
    case nothingRead
    case refused(PairingError)
}

/// What the person holding the phone should feel or hear.
public enum PairingFeedback: Equatable, Sendable {
    /// Their code was read.
    case readTheirs
    /// Both phones have each other's key; the contact is saved.
    case completed
    /// A refused code, the attempt timed out, or nothing was read.
    case failed
}

/// The waits around an attempt, in seconds. The confirmation timeout is
/// `FaceToFacePairing`'s.
public struct PairingTiming: Sendable {
    /// From completing to vibrating. Starting values, to be tuned on
    /// phones (2026-10-15).
    public var completionSignalDelay: TimeInterval
    /// How long the code stays up after completing.
    public var holdAfterCompletion: TimeInterval
    /// The code screen gives up after this long without reading anything,
    /// counted from when it opened. Ends about 10 s after the other phone's
    /// confirmation timeout, when that phone read this one but not the
    /// reverse (seen on phones, 2026-10-15).
    public var idleLimit: TimeInterval

    public init(completionSignalDelay: TimeInterval, holdAfterCompletion: TimeInterval, idleLimit: TimeInterval) {
        self.completionSignalDelay = completionSignalDelay
        self.holdAfterCompletion = holdAfterCompletion
        self.idleLimit = idleLimit
    }

    /// Ten minutes of idle in the Simulator, where codes are pasted by hand.
    public static var standard: PairingTiming {
#if targetEnvironment(simulator)
        PairingTiming(completionSignalDelay: 1, holdAfterCompletion: 3, idleLimit: 600)
#else
        PairingTiming(completionSignalDelay: 1, holdAfterCompletion: 3, idleLimit: 15)
#endif
    }
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
