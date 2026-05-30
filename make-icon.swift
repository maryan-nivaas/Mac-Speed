import AppKit
import Foundation

// Bakes Apple's rounded-rect "squircle" shape + transparent margin into the
// icon, so macOS shows a native-looking rounded tile instead of a sharp square.
let dir = "/Users/nivaasd/Developer/MacSpeed"
let srcPath = "\(dir)/mac-speed-logo.png"
let outPath = "\(dir)/icon-rounded-1024.png"

guard let src = NSImage(contentsOfFile: srcPath) else {
    FileHandle.standardError.write("cannot load source\n".data(using: .utf8)!)
    exit(1)
}

let canvas: CGFloat = 1024
let squircle: CGFloat = 824          // Apple's icon grid: ~80% of canvas
let inset = (canvas - squircle) / 2  // transparent margin (100px)
let radius: CGFloat = squircle * 0.2237   // ≈184, native corner curvature

let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
    pixelsWide: Int(canvas), pixelsHigh: Int(canvas),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
    isPlanar: false, colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: canvas, height: canvas)

let ctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = ctx
ctx.imageInterpolation = .high

let rect = NSRect(x: inset, y: inset, width: squircle, height: squircle)
NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
src.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)

NSGraphicsContext.restoreGraphicsState()

let data = rep.representation(using: .png, properties: [:])!
try! data.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
