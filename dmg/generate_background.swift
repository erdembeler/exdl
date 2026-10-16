import AppKit

// Renders the DMG window background (1x and 2x) next to this script.
// Run from the repository root:  swift dmg/generate_background.swift
//
// Finder always draws the icon labels itself, in black or white depending on the
// system appearance. The gradient is kept mid-tone so both stay readable.

// Window content size in points. Keep in sync with `window_rect` in dmg/settings.py.
let width: CGFloat = 660
let height: CGFloat = 400

// Vertical centre of the icon row, measured from the top. Keep in sync with
// `icon_locations` in dmg/settings.py.
let iconRowY: CGFloat = 238

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
}

func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: locations)!
}

func drawCentered(_ text: String, font: NSFont, color: NSColor, y: CGFloat, kern: CGFloat = 0, shadow: NSShadow? = nil) {
    var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .kern: kern]
    attributes[.shadow] = shadow
    let string = NSAttributedString(string: text, attributes: attributes)
    let size = string.size()
    string.draw(at: NSPoint(x: (width - size.width) / 2, y: height - y - size.height / 2))
}

func render(scale: CGFloat) -> CGImage {
    let context = CGContext(data: nil, width: Int(width * scale), height: Int(height * scale), bitsPerComponent: 8,
                            bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.scaleBy(x: scale, y: scale)
    context.interpolationQuality = .high

    // Base: azure gradient, top-left to bottom-right.
    context.drawLinearGradient(
        gradient([color(0x5FB4FF), color(0x3A80F5), color(0x2C5FDD)], [0, 0.6, 1]),
        start: CGPoint(x: 0, y: height), end: CGPoint(x: width, y: 0),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

    // Soft glows for luminosity: one in the top-left corner, a fainter one bottom-right.
    func glow(at center: CGPoint, radius: CGFloat, alpha: CGFloat) {
        context.drawRadialGradient(gradient([color(0xFFFFFF, alpha), color(0xFFFFFF, 0)], [0, 1]),
                                   startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
    }
    glow(at: CGPoint(x: 30, y: height - 10), radius: 260, alpha: 0.26)
    glow(at: CGPoint(x: width - 60, y: 40), radius: 300, alpha: 0.08)

    // Slight darkening towards the bottom edge for depth.
    context.drawLinearGradient(gradient([color(0x000000, 0), color(0x000000, 0.07)], [0, 1]),
                               start: CGPoint(x: 0, y: height * 0.45), end: CGPoint(x: 0, y: 0), options: [])

    // Three chevrons between the two icons, fading in towards the destination.
    let midY = height - iconRowY
    context.saveGState()
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.setLineWidth(5)
    context.setShadow(offset: CGSize(width: 0, height: -2), blur: 6, color: color(0x0A1F5C, 0.25))
    for (index, opacity) in [0.35, 0.65, 1.0].enumerated() {
        let x = width / 2 - 26 + CGFloat(index) * 26
        context.setStrokeColor(color(0xFFFFFF, CGFloat(opacity)))
        context.beginPath()
        context.move(to: CGPoint(x: x - 7, y: midY + 15))
        context.addLine(to: CGPoint(x: x + 7, y: midY))
        context.addLine(to: CGPoint(x: x - 7, y: midY - 15))
        context.strokePath()
    }
    context.restoreGState()

    // Header copy.
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(cgColor: color(0x0A1F5C, 0.22))
    shadow.shadowOffset = NSSize(width: 0, height: -1)
    shadow.shadowBlurRadius = 2
    drawCentered("Drag EXdl to Applications", font: .systemFont(ofSize: 25, weight: .semibold),
                 color: .white, y: 72, kern: -0.3, shadow: shadow)
    drawCentered("Then launch EXdl \u{2014} it lives in your menu bar.", font: .systemFont(ofSize: 13),
                 color: NSColor.white.withAlphaComponent(0.88), y: 102, shadow: shadow)
    NSGraphicsContext.restoreGraphicsState()

    return context.makeImage()!
}

func writePNG(_ image: CGImage, named name: String) throws {
    let representation = NSBitmapImageRep(cgImage: image)
    // Point size drives the PNG's pixel density: 2x images are tagged 144 dpi.
    representation.size = NSSize(width: width, height: height)
    let data = representation.representation(using: .png, properties: [:])!
    let directory = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
    try data.write(to: directory.appendingPathComponent(name))
}

try writePNG(render(scale: 1), named: "background.png")
try writePNG(render(scale: 2), named: "background@2x.png")
print("Wrote dmg/background.png and dmg/background@2x.png")
