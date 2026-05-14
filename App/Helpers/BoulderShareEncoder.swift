// BoulderShareEncoder.swift
//
// Packs the current boulder into a compact URL-safe base64 payload
// the website can render. Format (little-endian):
//
//   u8  version         (= 2)
//   u32 pixelCount      (up to 4B grains, plenty)
//   per pixel (8 bytes):
//     i8  x
//     i8  y
//     u8  hue   (hue * 255, rounded; 0xFF = legacy / no tag)
//     u8  shade (0..255, usually 0..19)
//     u32 earnedAt — UNIX seconds; 0 means "unknown" (legacy pixel)
//
// Pixels outside ±127 are clamped — never happens for our silhouette
// (the dome stays well inside that range).
//
// Author + rock name go in the URL query string as percent-encoded
// `by=` and `name=` so the binary payload stays purely geometric.
// The hash fragment carries the payload so it never hits server logs.

import Foundation

enum BoulderShareEncoder {
    /// Path-style base. The actual share URL is built per-call so we
    /// can append query params for name + author.
    static let shareBase = "https://boulder-43p.pages.dev/r/"

    static let payloadVersion: UInt8 = 2

    static func encode(pixels: [BoulderPixel], tags: [FocusTag]) -> String {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(5 + pixels.count * 8)
        bytes.append(payloadVersion)
        let n = UInt32(min(pixels.count, Int(UInt32.max)))
        bytes.append(UInt8(n & 0xFF))
        bytes.append(UInt8((n >> 8) & 0xFF))
        bytes.append(UInt8((n >> 16) & 0xFF))
        bytes.append(UInt8((n >> 24) & 0xFF))

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
            let ts: UInt32 = {
                guard let d = p.earnedAt else { return 0 }
                let secs = d.timeIntervalSince1970
                if secs <= 0 || secs > Double(UInt32.max) { return 0 }
                return UInt32(secs)
            }()
            bytes.append(UInt8(ts & 0xFF))
            bytes.append(UInt8((ts >> 8) & 0xFF))
            bytes.append(UInt8((ts >> 16) & 0xFF))
            bytes.append(UInt8((ts >> 24) & 0xFF))
        }

        let data = Data(bytes)
        return base64URLEncode(data)
    }

    static func shareURL(for model: BoulderModel) -> URL? {
        let payload = encode(pixels: model.pixels, tags: model.tags)
        var queryItems: [URLQueryItem] = []
        if let n = model.userFirstName?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
            queryItems.append(URLQueryItem(name: "by", value: n))
        }
        if let rn = model.rockName?.trimmingCharacters(in: .whitespacesAndNewlines), !rn.isEmpty {
            queryItems.append(URLQueryItem(name: "name", value: rn))
        }
        var comp = URLComponents(string: shareBase)
        if !queryItems.isEmpty { comp?.queryItems = queryItems }
        comp?.fragment = payload
        return comp?.url
    }

    private static func base64URLEncode(_ data: Data) -> String {
        var s = data.base64EncodedString()
        s = s.replacingOccurrences(of: "+", with: "-")
        s = s.replacingOccurrences(of: "/", with: "_")
        s = s.replacingOccurrences(of: "=", with: "")
        return s
    }
}
