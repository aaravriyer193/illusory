import AppKit

// Rasterise the app-icon SVG at every size macOS asks for. NSImage decodes SVG,
// so the icon and the logo stay one artwork rather than two that drift.
let source = URL(fileURLWithPath: "assets/appicon.svg")
let outDir = URL(fileURLWithPath: "build/Illusory.iconset")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

guard let data = try? Data(contentsOf: source), let art = NSImage(data: data) else {
    print("could not load \(source.path)"); exit(1)
}

let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for variant in variants {
    let side = variant.pixels
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                     isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0) else { continue }
    rep.size = NSSize(width: side, height: side)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    art.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else { continue }
    try? png.write(to: outDir.appendingPathComponent("\(variant.name).png"))
}
print("wrote \(variants.count) sizes")
