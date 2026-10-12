//
//  PairingQRCode.swift
//  PairingKit
//

import Foundation
import CoreImage

public enum PairingQRCode {

    /// How much damage the code survives. Less correction means fewer,
    /// larger squares for the same text — easier to read small or out of
    /// focus, which is the usual problem with a code shown on a clean screen.
    public enum ErrorCorrection: String, Sendable {
        case low = "L"
        case medium = "M"
    }

    /// A QR code image for `text` (normally `PairingPayload.encoded()`).
    ///
    /// - Parameter scale: pixels per QR module. Draw the result without
    ///   interpolation; a smoothed code scans badly.
    public static func image(for text: String, scale: Int = 10,
                             errorCorrection: ErrorCorrection = .medium) -> CGImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue(errorCorrection.rawValue, forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: CGFloat(scale), y: CGFloat(scale)))
        return CIContext().createCGImage(scaled, from: scaled.extent)
    }
}
