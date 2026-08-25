// make_icon.swift — generates assets/Automater.iconset → Automater.icns
//
// Fully original artwork drawn with CoreGraphics (no external assets, no
// licensing questions). Design: macOS squircle, indigo gradient, click
// ripples radiating from a cursor-arrow hotspot.
//
// Run:  swift scripts/make_icon.swift
// Then: iconutil -c icns assets/Automater.iconset -o assets/Automater.icns

import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("assets")
    .appendingPathComponent("Automater.iconset", isDirectory: true)

func srgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

/// Parametric superellipse — reads as the native macOS squircle.
func squircle(_ rect: CGRect) -> CGPath {
    let n: CGFloat = 4.8
    let cx = rect.midX, cy = rect.midY
    let a = rect.width / 2, b = rect.height / 2
    let path = CGMutablePath()
    let steps = 720
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let ct = cos(t), st = sin(t)
        let x = cx + a * (ct < 0 ? -1 : 1) * pow(abs(ct), 2 / n)
        let y = cy + b * (st < 0 ? -1 : 1) * pow(abs(st), 2 / n)
        if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
        else { path.addLine(to: CGPoint(x: x, y: y)) }
    }
    path.closeSubpath()
    return path
}

func render(side: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: side, height: side))
    image.lockFocus()
    defer { image.unlockFocus() }
    guard let ctx = NSGraphicsContext.current?.cgContext else { return image }

    let u = side / 1024
    let inset = 100 * u
    let rect = CGRect(x: inset, y: inset, width: side - 2 * inset, height: side - 2 * inset)
    let shell = squircle(rect)

    // --- background gradient ---
    ctx.saveGState()
    ctx.addPath(shell)
    ctx.clip()
    let grad = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [srgb(0.20, 0.12, 0.55), srgb(0.04, 0.06, 0.24)] as CFArray,
        locations: [0, 1])!
    ctx.drawLinearGradient(
        grad,
        start: CGPoint(x: rect.midX, y: rect.maxY),
        end: CGPoint(x: rect.midX, y: rect.minY),
        options: [])

    // soft radial lift behind the glyph
    let glow = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [srgb(1, 1, 1, 0.20), srgb(1, 1, 1, 0)] as CFArray,
        locations: [0, 1])!
    let glowCenter = CGPoint(x: rect.midX, y: rect.midY + 60 * u)
    ctx.drawRadialGradient(glow,
                           startCenter: glowCenter, startRadius: 0,
                           endCenter: glowCenter, endRadius: 430 * u,
                           options: [])
    ctx.restoreGState()

    // --- click ripples, clipped to the shell ---
    let hotspot = CGPoint(x: rect.midX - 66 * u, y: rect.midY + 74 * u)
    ctx.saveGState()
    ctx.addPath(shell)
    ctx.clip()
    let ripples: [(radius: CGFloat, width: CGFloat, alpha: CGFloat)] = [
        (150 * u, 24 * u, 0.68),
        (238 * u, 18 * u, 0.38),
        (330 * u, 14 * u, 0.22),
    ]
    for r in ripples {
        ctx.setStrokeColor(srgb(1, 1, 1, r.alpha))
        ctx.setLineWidth(r.width)
        ctx.strokeEllipse(in: CGRect(
            x: hotspot.x - r.radius, y: hotspot.y - r.radius,
            width: r.radius * 2, height: r.radius * 2))
    }
    // impact point where ripples converge
    ctx.setFillColor(srgb(0.30, 0.96, 1, 0.95))
    ctx.fillEllipse(in: CGRect(
        x: hotspot.x - 20 * u, y: hotspot.y - 20 * u, width: 40 * u, height: 40 * u))
    ctx.restoreGState()

    // --- cursor arrow (classic silhouette, tip on the hotspot) ---
    let arrowUnits: [(CGFloat, CGFloat)] = [
        (5.5, 3.21), (5.5, 20.79), (10.06, 16.33), (12.87, 22.25),
        (16.13, 20.71), (13.35, 14.83), (19.62, 14.83),
    ]
    let s: CGFloat = 23 * u
    let arrow = CGMutablePath()
    for (i, pt) in arrowUnits.enumerated() {
        let x = hotspot.x + (pt.0 - 5.5) * s
        let y = hotspot.y - (pt.1 - 3.21) * s   // flip: source space is y-down
        if i == 0 { arrow.move(to: CGPoint(x: x, y: y)) }
        else { arrow.addLine(to: CGPoint(x: x, y: y)) }
    }
    arrow.closeSubpath()

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 5 * u, height: -9 * u),
                  blur: 22 * u, color: srgb(0.02, 0.05, 0.25, 0.45))
    ctx.addPath(arrow)
    ctx.setFillColor(srgb(0.98, 0.99, 1))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(arrow)
    ctx.setStrokeColor(srgb(0.22, 0.10, 0.52, 0.55))
    ctx.setLineWidth(3 * u)
    ctx.strokePath()

    // --- top sheen + inner rim ---
    ctx.saveGState()
    ctx.addPath(shell)
    ctx.clip()
    let sheen = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [srgb(1, 1, 1, 0.16), srgb(1, 1, 1, 0)] as CFArray,
        locations: [0, 1])!
    ctx.drawLinearGradient(sheen,
                           start: CGPoint(x: rect.midX, y: rect.maxY),
                           end: CGPoint(x: rect.midX, y: rect.maxY - 300 * u),
                           options: [])
    ctx.restoreGState()

    ctx.addPath(shell)
    ctx.setStrokeColor(srgb(1, 1, 1, 0.10))
    ctx.setLineWidth(2 * u)
    ctx.strokePath()

    return image
}

// MARK: - Write iconset

try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

let entries: [(size: Int, name: String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

for entry in entries {
    let img = render(side: CGFloat(entry.size))
    guard let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write("failed to encode \(entry.name)\n".data(using: .utf8)!)
        continue
    }
    let url = root.appendingPathComponent(entry.name)
    try png.write(to: url)
    print("wrote \(url.path)")
}

print("done — now: iconutil -c icns \"\(root.path)\" -o \"\(root.deletingLastPathComponent().appendingPathComponent("Automater.icns").path)\"")
