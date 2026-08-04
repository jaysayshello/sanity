import AppKit

// Renders a 1024x1024 macOS app icon: a rounded squircle with a blue-indigo
// gradient and a white checklist glyph. Output path is arg 1 (default below).

let outPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "icon/icon-1024.png"

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

// Rounded squircle (macOS icon art sits inset with a large corner radius).
let inset: CGFloat = 100
let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let shape = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)

let top = NSColor(calibratedRed: 0.36, green: 0.55, blue: 0.96, alpha: 1)
let bottom = NSColor(calibratedRed: 0.35, green: 0.36, blue: 0.90, alpha: 1)
NSGraphicsContext.saveGraphicsState()
shape.addClip()
NSGradient(colors: [top, bottom])?.draw(in: rect, angle: 270)
NSGraphicsContext.restoreGraphicsState()

// White checklist glyph, tinted and centered.
func tinted(_ img: NSImage, _ color: NSColor) -> NSImage {
    let out = NSImage(size: img.size)
    out.lockFocus()
    color.set()
    let r = NSRect(origin: .zero, size: img.size)
    img.draw(in: r)
    r.fill(using: .sourceAtop)
    out.unlockFocus()
    return out
}

let config = NSImage.SymbolConfiguration(pointSize: 430, weight: .semibold)
if let symbol = NSImage(systemSymbolName: "checklist", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) {
    let white = tinted(symbol, .white)
    let s = white.size
    let origin = NSPoint(x: (size - s.width) / 2, y: (size - s.height) / 2)
    white.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("failed to render\n".data(using: .utf8)!)
    exit(1)
}
try? png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
