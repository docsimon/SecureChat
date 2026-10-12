//
//  QRCodeScannerView.swift
//  PairingKit
//
//  A camera preview that reports the text of any QR code it sees. It knows
//  nothing about pairing: hand what it reports to `Pairing.evaluate`.
//
//  The host app must declare NSCameraUsageDescription. There is no camera in
//  the Simulator; `onFailure(.cameraUnavailable)` is what happens there.
//

#if canImport(UIKit)
import SwiftUI
import AVFoundation

public struct QRCodeScannerView: UIViewControllerRepresentable {

    public enum Failure: Equatable, Sendable {
        case cameraUnavailable
        case accessDenied
    }

    public enum Camera: Equatable, Sendable {
        /// The usual one: the user aims at the other screen.
        case back
        /// For two phones held face to face, each reading the other's screen.
        case front
    }

    private let camera: Camera
    private let onCode: @MainActor (String) -> Void
    private let onFailure: @MainActor (Failure) -> Void

    /// - Parameter onCode: called on the main actor. The same code is not
    ///   reported again while it stays in view (at most once every 2 s).
    public init(camera: Camera = .back,
                onCode: @escaping @MainActor (String) -> Void,
                onFailure: @escaping @MainActor (Failure) -> Void = { _ in }) {
        self.camera = camera
        self.onCode = onCode
        self.onFailure = onFailure
    }

    public func makeUIViewController(context: Context) -> UIViewController {
        QRCodeScannerViewController(camera: camera, onCode: onCode, onFailure: onFailure)
    }

    public func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        (uiViewController as? QRCodeScannerViewController)?.setCamera(camera)
    }
}

/// `AVCaptureSession` must be started and stopped off the main thread, and it
/// is not Sendable. All use of it goes through `queue`.
private final class CaptureSessionBox: @unchecked Sendable {
    let session = AVCaptureSession()
    let queue = DispatchQueue(label: "pairingkit.qrscanner.session")

    func start() {
        queue.async { [self] in
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }
}

private final class QRCodeScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {

    private let onCode: @MainActor (String) -> Void
    private let onFailure: @MainActor (QRCodeScannerView.Failure) -> Void
    private let capture = CaptureSessionBox()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var camera: QRCodeScannerView.Camera
    private var input: AVCaptureDeviceInput?
    private var isConfigured = false
    private var lastReported: (code: String, at: Date)?

    init(camera: QRCodeScannerView.Camera,
         onCode: @escaping @MainActor (String) -> Void,
         onFailure: @escaping @MainActor (QRCodeScannerView.Failure) -> Void) {
        self.camera = camera
        self.onCode = onCode
        self.onFailure = onFailure
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        Task { await configure() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if isConfigured { capture.start() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        capture.stop()
    }

    private func configure() async {
        guard await AVCaptureDevice.requestAccess(for: .video) else {
            onFailure(.accessDenied)
            return
        }
        let session = capture.session
        let output = AVCaptureMetadataOutput()
        guard let input = Self.makeInput(for: camera),
              session.canAddInput(input), session.canAddOutput(output) else {
            onFailure(.cameraUnavailable)
            return
        }
        session.addInput(input)
        self.input = input
        session.addOutput(output)
        // Only after the output is attached: the available types depend on it.
        guard output.availableMetadataObjectTypes.contains(.qr) else {
            onFailure(.cameraUnavailable)
            return
        }
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        previewLayer = layer

        isConfigured = true
        capture.start()
    }

    func setCamera(_ newCamera: QRCodeScannerView.Camera) {
        guard newCamera != camera else { return }
        camera = newCamera
        // Before the first configuration there is nothing to swap; `configure`
        // reads `camera` when it gets there.
        guard isConfigured else { return }
        let session = capture.session
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if let input { session.removeInput(input) }
        input = nil
        guard let replacement = Self.makeInput(for: newCamera), session.canAddInput(replacement) else {
            onFailure(.cameraUnavailable)
            return
        }
        session.addInput(replacement)
        input = replacement
        lastReported = nil
    }

    private static func makeInput(for camera: QRCodeScannerView.Camera) -> AVCaptureDeviceInput? {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video,
                                                   position: camera == .front ? .front : .back) else {
            return nil
        }
        // A phone screen is read from close up. Front cameras on older phones
        // have fixed focus and support neither setting.
        if (try? device.lockForConfiguration()) != nil {
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isAutoFocusRangeRestrictionSupported {
                device.autoFocusRangeRestriction = .near
            }
            device.unlockForConfiguration()
        }
        return try? AVCaptureDeviceInput(device: device)
    }

    nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput,
                                    didOutput metadataObjects: [AVMetadataObject],
                                    from connection: AVCaptureConnection) {
        let codes = metadataObjects.compactMap { ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }
        guard let code = codes.first else { return }
        Task { @MainActor in self.report(code) }
    }

    private func report(_ code: String) {
        let now = Date()
        if let last = lastReported, last.code == code, now.timeIntervalSince(last.at) < 2 {
            lastReported = (code, now)
            return
        }
        lastReported = (code, now)
        onCode(code)
    }
}
#endif
