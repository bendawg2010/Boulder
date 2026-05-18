// QRCodeImage.swift
//
// Generates a tinted QR code as an NSImage from a string. Used by the
// Pair Device sheet to encode the boulder web app URL + sync_id so a
// phone scan opens the matching rock.

import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

enum QRCodeImage {
    /// Render `string` to an NSImage at `size` pixels square. Foreground
    /// is white, background transparent — meant for dark backgrounds.
    static func make(from string: String, size: CGFloat = 240) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let baseImage = filter.outputImage else { return nil }

        // Scale up to the requested pixel size using nearest-neighbor
        // so the QR squares stay crisp.
        let scale = size / baseImage.extent.width
        let scaled = baseImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        // Replace black -> white, white -> transparent so the QR reads
        // on the dark gradient backdrop.
        guard let inverted = CIFilter(name: "CIColorInvert",
                                      parameters: [kCIInputImageKey: scaled])?.outputImage,
              let masked = CIFilter(name: "CIMaskToAlpha",
                                    parameters: [kCIInputImageKey: inverted])?.outputImage
        else { return nil }

        let ctx = CIContext()
        guard let cg = ctx.createCGImage(masked, from: masked.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: size, height: size))
    }
}
