#!/usr/bin/env swift
// Generates Kestrel's app icon — a 1024×1024 master PNG rendered from the same brand marks
// as the UI: a teal→indigo squircle, a white bird glyph, and the health-gauge ring motif.
// Original artwork (no third-party cleaner assets — see docs/LEGAL.md). Run: swift scripts/make-icon.swift <out.png>
import AppKit

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dist/icon-master.png"
let S: CGFloat = 1024

// Brand colors (match Sources/KestrelApp/Palette.swift).
func hex(_ v: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255, alpha: 1)
}
let teal = hex(0x12C2B0), indigo = hex(0x4F6EF5)

let image = NSImage(size: NSSize(width: S, height: S))
image.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else { fatalError("no context") }

// Rounded "squircle" occupying the Apple icon grid (~82% of the canvas, continuous corners).
let inset = S * 0.09
let box = CGRect(x: inset, y: inset, width: S - 2 * inset, height: S - 2 * inset)
let corner = box.width * 0.2237
let squircle = NSBezierPath(roundedRect: box, xRadius: corner, yRadius: corner)

// Diagonal teal→indigo gradient fill.
ctx.saveGState()
squircle.addClip()
let grad = NSGradient(colors: [teal, indigo])!
grad.draw(from: CGPoint(x: box.minX, y: box.maxY), to: CGPoint(x: box.maxX, y: box.minY), options: [])
// Soft top-light sheen.
let sheen = NSGradient(colors: [NSColor(white: 1, alpha: 0.18), NSColor(white: 1, alpha: 0)])!
sheen.draw(from: CGPoint(x: box.midX, y: box.maxY), to: CGPoint(x: box.midX, y: box.midY), options: [])
ctx.restoreGState()

// The health-gauge ring: a full quiet track plus a bright arc that sweeps ~78%, echoing the
// menu-bar gauge. Centered, sized to frame the bird.
let center = CGPoint(x: box.midX, y: box.midY)
let ringR = box.width * 0.335
let lineW = box.width * 0.052
func arc(from a: CGFloat, to b: CGFloat) -> NSBezierPath {
    let p = NSBezierPath()
    p.appendArc(withCenter: center, radius: ringR, startAngle: a, endAngle: b, clockwise: false)
    p.lineWidth = lineW
    p.lineCapStyle = .round
    return p
}
NSColor(white: 1, alpha: 0.22).setStroke(); arc(from: 0, to: 360).stroke()
NSColor.white.setStroke(); arc(from: 130, to: 130 + 281).stroke()   // ~78% sweep, starting bottom-left

// White bird glyph, centered inside the ring.
let cfg = NSImage.SymbolConfiguration(pointSize: 360, weight: .semibold)
if let sym = NSImage(systemSymbolName: "bird.fill", accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
    let bw = sym.size.width, bh = sym.size.height
    let scale = (box.width * 0.40) / max(bw, bh)
    let dw = bw * scale, dh = bh * scale
    let rect = CGRect(x: center.x - dw / 2, y: center.y - dh / 2, width: dw, height: dh)
    let white = NSImage(size: NSSize(width: dw, height: dh))
    white.lockFocus()
    sym.draw(in: CGRect(x: 0, y: 0, width: dw, height: dh))
    NSColor.white.set()
    CGRect(x: 0, y: 0, width: dw, height: dh).fill(using: .sourceAtop)
    white.unlockFocus()
    // Subtle drop shadow so the bird lifts off the gradient.
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 18, color: NSColor(white: 0, alpha: 0.22).cgColor)
    white.draw(in: rect)
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { fatalError("encode failed") }
try! png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
