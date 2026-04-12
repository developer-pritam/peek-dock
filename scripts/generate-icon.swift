#!/usr/bin/env swift
// generate-icon.swift — generates PeekDock app icon PNG files
// Usage: swift scripts/generate-icon.swift
// Output: WindowManager/Assets.xcassets/AppIcon.appiconset/

import AppKit
import Foundation

// MARK: - Drawing

func drawIcon(_ s: CGFloat) -> NSImage {
    NSImage(size: NSSize(width: s, height: s), flipped: false) { _ in
        guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

        // ── 1. Background gradient (blue top-left → purple bottom-right) ──
        let cs = CGColorSpaceCreateDeviceRGB()
        let gradient = CGGradient(
            colorSpace: cs,
            colorComponents: [0.16, 0.32, 0.94, 1,   // blue (start = top-left in Quartz)
                               0.50, 0.13, 0.86, 1],  // purple (end = bottom-right)
            locations: [0, 1], count: 2)!
        ctx.drawLinearGradient(gradient,
            start: CGPoint(x: 0, y: s), end: CGPoint(x: s, y: 0), options: [])

        // ── 2. Preview card (white frosted panel, upper-center area) ──
        let cw = s * 0.62, ch = s * 0.40, cr = s * 0.045
        let cx = (s - cw) / 2
        let cy = s * 0.44   // bottom of card from Quartz origin (bottom = 0)

        // Drop shadow behind card
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.018),
                      blur: s * 0.065,
                      color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.45))
        let cardPath = CGPath(roundedRect: CGRect(x: cx, y: cy, width: cw, height: ch),
                              cornerWidth: cr, cornerHeight: cr, transform: nil)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.93))
        ctx.addPath(cardPath)
        ctx.fillPath()
        ctx.restoreGState()

        // Window thumbnail 1 (blue tint)
        let tw = cw * 0.36, th = ch * 0.54, tr = s * 0.018
        let t1x = cx + cw * 0.08,  ty = cy + ch * 0.24
        ctx.setFillColor(CGColor(red: 0.16, green: 0.32, blue: 0.94, alpha: 0.20))
        ctx.addPath(CGPath(roundedRect: CGRect(x: t1x, y: ty, width: tw, height: th),
                           cornerWidth: tr, cornerHeight: tr, transform: nil))
        ctx.fillPath()

        // Window thumbnail 2 (purple tint)
        let t2x = cx + cw * 0.56
        ctx.setFillColor(CGColor(red: 0.50, green: 0.13, blue: 0.86, alpha: 0.20))
        ctx.addPath(CGPath(roundedRect: CGRect(x: t2x, y: ty, width: tw, height: th),
                           cornerWidth: tr, cornerHeight: tr, transform: nil))
        ctx.fillPath()

        // Thin title line below each thumbnail (simulates window label)
        ctx.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 0.25))
        let lh = s * 0.013, lw = tw * 0.65
        for tx in [t1x + (tw - lw) / 2, t2x + (tw - lw) / 2] {
            ctx.fill(CGRect(x: tx, y: ty - s * 0.04, width: lw, height: lh))
        }

        // ── 3. Dock bar (white translucent pill at bottom) ──
        let dw = s * 0.70, dh = s * 0.155
        let dx = (s - dw) / 2, dy = s * 0.08

        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.18))
        let dockPath = CGPath(roundedRect: CGRect(x: dx, y: dy, width: dw, height: dh),
                              cornerWidth: dh / 2, cornerHeight: dh / 2, transform: nil)
        ctx.addPath(dockPath)
        ctx.fillPath()

        // Three app icons on dock
        let ic = dh * 0.54   // icon circle diameter
        let iy = dy + (dh - ic) / 2
        let dockColors: [(CGFloat, CGFloat, CGFloat)] = [
            (1.00, 0.55, 0.28),  // orange
            (0.28, 0.86, 0.52),  // green
            (1.00, 1.00, 1.00),  // white — the "hovered" / active icon
        ]
        for i in 0..<3 {
            let ix = dx + dw / 4 * CGFloat(i + 1) - ic / 2
            let (r, g, b) = dockColors[i]
            ctx.setFillColor(CGColor(red: r, green: g, blue: b, alpha: i == 2 ? 1.0 : 0.88))
            ctx.fillEllipse(in: CGRect(x: ix, y: iy, width: ic, height: ic))
        }

        // Glow on the active (rightmost, white) dock icon
        let activeIx = dx + dw / 4 * 3 - ic / 2
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: s * 0.038,
                      color: CGColor(red: 1, green: 1, blue: 1, alpha: 0.85))
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1.0))
        ctx.fillEllipse(in: CGRect(x: activeIx, y: iy, width: ic, height: ic))
        ctx.restoreGState()

        // Dot below active icon (Dock "running" indicator)
        let dotR = s * 0.018
        let dotX = activeIx + ic / 2 - dotR / 2
        let dotY = dy - dotR * 1.6
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.75))
        ctx.fillEllipse(in: CGRect(x: dotX, y: dotY, width: dotR, height: dotR))

        return true
    }
}

// MARK: - Save PNG

func savePNG(_ image: NSImage, to path: String) throws {
    var rect = NSRect(origin: .zero, size: image.size)
    guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
        throw NSError(domain: "Icon", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "CGImage conversion failed"])
    }
    let rep = NSBitmapImageRep(cgImage: cg)
    rep.size = image.size
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "Icon", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "PNG encoding failed"])
    }
    try data.write(to: URL(fileURLWithPath: path))
}

// MARK: - Main

let projectRoot = URL(fileURLWithPath: #file).deletingLastPathComponent().deletingLastPathComponent().path
let outDir = "\(projectRoot)/WindowManager/Assets.xcassets/AppIcon.appiconset"
try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

// (baseSize, scale) pairs required by macOS
let specs: [(Int, Int)] = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2),
]

for (base, scale) in specs {
    let renderSize = CGFloat(base * scale)
    let img = drawIcon(renderSize)
    let filename = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
    do {
        try savePNG(img, to: "\(outDir)/\(filename)")
        print("  ✓ \(filename)  (\(Int(renderSize))px)")
    } catch {
        print("  ✗ \(filename): \(error.localizedDescription)")
    }
}

print("\nIcons written to:\n  \(outDir)")
