import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let iconset = output.appendingPathComponent("QuickNotes.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
func icon(_ size: Int) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let factor = CGFloat(size) / 1024
    let transform = AffineTransform(scale: factor)
    (transform as NSAffineTransform).concat()
    let background = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 204, yRadius: 204)
    NSGradient(starting: NSColor(calibratedRed: 0.97, green: 0.74, blue: 0.40, alpha: 1),
        ending: NSColor(calibratedRed: 0.92, green: 0.41, blue: 0.29, alpha: 1))!.draw(in: background, angle: -60)
    let paper = NSBezierPath(roundedRect: NSRect(x: 235, y: 208, width: 554, height: 622), xRadius: 62, yRadius: 62)
    NSColor(calibratedWhite: 1, alpha: 0.94).setFill(); paper.fill()
    let ink = NSColor(calibratedRed: 0.49, green: 0.27, blue: 0.19, alpha: 1)
    for y in [646.0, 502.0, 358.0] {
        let box = NSBezierPath(roundedRect: NSRect(x: 310, y: y, width: 51, height: 51), xRadius: 14, yRadius: 14)
        ink.withAlphaComponent(0.65).setStroke(); box.lineWidth = 9; box.stroke()
        let line = NSBezierPath(roundedRect: NSRect(x: 405, y: y + 17, width: y == 358 ? 190 : 285, height: 17), xRadius: 8, yRadius: 8)
        ink.withAlphaComponent(y == 646 ? 0.8 : 0.35).setFill(); line.fill()
    }
    let check = NSBezierPath()
    check.move(to: NSPoint(x: 317, y: 675)); check.line(to: NSPoint(x: 333, y: 658)); check.line(to: NSPoint(x: 360, y: 690))
    ink.setStroke(); check.lineWidth = 9; check.lineCapStyle = .round; check.lineJoinStyle = .round; check.stroke()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 2 ? "@2x" : ""
        try icon(points * scale).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
    }
}
try icon(1024).write(to: output.appendingPathComponent("QuickNotes.png"))
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", output.appendingPathComponent("QuickNotes.icns").path]
try process.run(); process.waitUntilExit()
if process.terminationStatus != 0 { exit(process.terminationStatus) }
try FileManager.default.removeItem(at: iconset)
