import AppKit

let destination = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = destination.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
var chunks = Data()
func bigEndianSize(_ value: Int) -> Data {
    var number = UInt32(value).bigEndian
    return withUnsafeBytes(of: &number) { Data($0) }
}
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let representation = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                               isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)
        let factor = CGFloat(pixels) / 1024
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: factor, y: factor)
        NSColor(red: 0.94, green: 0.94, blue: 0.91, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 62, y: 62, width: 900, height: 900), xRadius: 208, yRadius: 208).fill()
        let path = NSBezierPath()
        path.appendOval(in: NSRect(x: 240, y: 375, width: 270, height: 270))
        path.move(to: NSPoint(x: 510, y: 510)); path.line(to: NSPoint(x: 780, y: 510))
        path.move(to: NSPoint(x: 690, y: 510)); path.line(to: NSPoint(x: 690, y: 400))
        path.move(to: NSPoint(x: 780, y: 510)); path.line(to: NSPoint(x: 780, y: 425))
        path.lineWidth = 61; path.lineCapStyle = .round; path.lineJoinStyle = .round
        NSColor(red: 0.78, green: 0.31, blue: 0.20, alpha: 1).setStroke(); path.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        let png = representation.representation(using: .png, properties: [:])!
        try png.write(to: iconset.appendingPathComponent(name))
        let types = [16: ["icp4", "ic11"], 32: ["icp5", "ic12"], 128: ["ic07", "ic13"],
                     256: ["ic08", "ic14"], 512: ["ic09", "ic10"]]
        chunks.append(Data(types[size]![scale - 1].utf8))
        chunks.append(bigEndianSize(png.count + 8))
        chunks.append(png)
    }
}
// ICNS is a big-endian chunk container. PNG chunks avoid iconutil's dependency
// on system image-conversion services, so this also builds in restricted hosts.
var icon = Data("icns".utf8)
icon.append(bigEndianSize(chunks.count + 8))
icon.append(chunks)
try icon.write(to: destination.appendingPathComponent("AppIcon.icns"))
try FileManager.default.removeItem(at: iconset)
