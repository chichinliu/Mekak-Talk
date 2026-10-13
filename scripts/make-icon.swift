import AppKit

let output = CommandLine.arguments[1]
let temp = FileManager.default.temporaryDirectory.appendingPathComponent("HydayTalkIcon-" + UUID().uuidString)
let folder = temp.appendingPathExtension("iconset")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: folder) }
for (name, size) in [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64), ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512), ("icon_512x512", 512), ("icon_512x512@2x", 1024)] {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let scale = CGFloat(size) / 1024
    let rect = NSRect(x: 72 * scale, y: 72 * scale, width: 880 * scale, height: 880 * scale)
    NSColor(Palette.accent).setFill()
    NSBezierPath(roundedRect: rect, xRadius: 200 * scale, yRadius: 200 * scale).fill()
    NSColor(Palette.onAccent).setFill()
    // The mark spans 72% of the tile, matching HydayLogo.
    let unit = rect.width * 0.72 / 100, origin = CGPoint(x: rect.minX + rect.width * 0.14, y: rect.minY + rect.height * 0.14)
    for bar in DesignTokens.Logo.bars {
        let w = bar.width * unit, h = bar.height * unit
        NSBezierPath(roundedRect: NSRect(x: origin.x + bar.x * unit - w / 2, y: origin.y + 50 * unit - h / 2, width: w, height: h),
                     xRadius: w / 2, yRadius: w / 2).fill()
    }
    image.unlockFocus()
    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
    try rep.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(name + ".png"))
}
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", folder.path, "-o", output]
try process.run(); process.waitUntilExit()
guard process.terminationStatus == 0 else { fatalError("iconutil failed") }
