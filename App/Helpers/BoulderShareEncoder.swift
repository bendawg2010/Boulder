// BoulderShareEncoder.swift
//
// Packs the current boulder into a compact URL-safe base64 payload
// the website can render. Format (little-endian):
//
//   u8  version         (= 1)
//   u16 pixelCount
//   per pixel (4 bytes):
//     i8  x
//     i8  y
//     u8  hue   (hue * 255, rounded; 0xFF = legacy / no tag)
//     u8  shade (0..255, usually 0..19)
//
// Pixels outside ±127 are clamped — never happens for our silhouette
// (the dome stays well inside that range).

import Foundation

enum BoulderShareEncoder {
    static let shareBaseURL = "https://boulder-43p.pages.dev/r/"

    static func encode(pixels: [BoulderPixel], tags: [FocusTag]) -> String {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(3 + pixels.count * 4)
        bytes.append(1)
        let n = UInt16(min(pixels.count, Int(UInt16.max)))
        bytes.append(UInt8(n & 0xFF))
        bytes.append(UInt8((n >> 8) & 0xFF))

        let hueByID: [UUID: Double] = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0.hue) })

        for p in pixels.prefix(Int(n)) {
            bytes.append(UInt8(bitPattern: Int8(clamping: p.x)))
            bytes.append(UInt8(bitPattern: Int8(clamping: p.y)))
            if let id = p.tagID, let hue = hueByID[id] {
                bytes.append(UInt8(max(0, min(254, Int(hue * 255)))))
            } else {
                bytes.append(0xFF)
            }
            bytes.append(UInt8(max(0, min(255, p.shade))))
        }

        let data = Data(bytes)
        return base64URLEncode(data)
    }

    static func shareURL(for model: BoulderModel) -> URL? {
        let payload = encode(pixels: model.pixels, tags: model.tags)
        return URL(string: shareBaseURL + payload)
    }

    private static func base64URLEncode(_ data: Data) -> String {
        var s = data.base64EncodedString()
        s = s.replacingOccurrences(of: "+", with: "-")
        s = s.replacingOccurrences(of: "/", with: "_")
        s = s.replacingOccurrences(of: "=", with: "")
        return s
    }
}
