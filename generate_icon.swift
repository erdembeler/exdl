import Cocoa

func createIconImage(size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        img.unlockFocus()
        return img
    }
    
    // Squircle container with Apple rounded rect radius (~0.224 * size)
    let rect = NSRect(x: size * 0.08, y: size * 0.08, width: size * 0.84, height: size * 0.84)
    let cornerRadius = size * 0.19
    let clipPath = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
    
    ctx.saveGState()
    clipPath.addClip()
    
    // Background gradient: Deep Space Blue to Vibrant Cyan/Teal
    let colors = [
        NSColor(red: 0.06, green: 0.12, blue: 0.28, alpha: 1.0).cgColor,
        NSColor(red: 0.10, green: 0.40, blue: 0.75, alpha: 1.0).cgColor,
        NSColor(red: 0.00, green: 0.65, blue: 0.85, alpha: 1.0).cgColor
    ] as CFArray
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 0.6, 1.0]) {
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])
    }
    ctx.restoreGState()
    
    // Inner subtle glow border
    ctx.saveGState()
    let borderPath = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: cornerRadius - 1, yRadius: cornerRadius - 1)
    NSColor.white.withAlphaComponent(0.25).setStroke()
    borderPath.lineWidth = max(1.0, size * 0.015)
    borderPath.stroke()
    ctx.restoreGState()
    
    // Draw Symbol: External Drive + Link badge
    // 1. External Drive Base Box
    let driveWidth = size * 0.46
    let driveHeight = size * 0.28
    let driveX = (size - driveWidth) / 2
    let driveY = size * 0.40
    let driveRect = NSRect(x: driveX, y: driveY, width: driveWidth, height: driveHeight)
    let driveCorner = size * 0.05
    
    let drivePath = NSBezierPath(roundedRect: driveRect, xRadius: driveCorner, yRadius: driveCorner)
    NSColor.white.withAlphaComponent(0.92).setFill()
    drivePath.fill()
    
    // Drive LED light indicator
    let ledSize = size * 0.03
    let ledRect = NSRect(x: driveX + driveWidth - size * 0.07, y: driveY + driveHeight / 2 - ledSize / 2, width: ledSize, height: ledSize)
    let ledPath = NSBezierPath(ovalIn: ledRect)
    NSColor(red: 0.2, green: 0.85, blue: 0.4, alpha: 1.0).setFill()
    ledPath.fill()
    
    // Drive slot line
    let slotPath = NSBezierPath()
    let slotY = driveY + driveHeight * 0.5
    slotPath.move(to: NSPoint(x: driveX + size * 0.06, y: slotY))
    slotPath.line(to: NSPoint(x: driveX + driveWidth - size * 0.12, y: slotY))
    slotPath.lineWidth = max(1.5, size * 0.02)
    slotPath.lineCapStyle = .round
    NSColor(white: 0.65, alpha: 0.8).setStroke()
    slotPath.stroke()
    
    // 2. Applications Arrow/Link Symbol above the drive
    let arrowPath = NSBezierPath()
    let arrowCenterX = size * 0.5
    let arrowTopY = size * 0.75
    let arrowBottomY = size * 0.56
    
    arrowPath.move(to: NSPoint(x: arrowCenterX, y: arrowTopY))
    arrowPath.line(to: NSPoint(x: arrowCenterX, y: arrowBottomY))
    arrowPath.move(to: NSPoint(x: arrowCenterX - size * 0.08, y: arrowBottomY + size * 0.08))
    arrowPath.line(to: NSPoint(x: arrowCenterX, y: arrowBottomY))
    arrowPath.line(to: NSPoint(x: arrowCenterX + size * 0.08, y: arrowBottomY + size * 0.08))
    
    arrowPath.lineWidth = max(2.5, size * 0.035)
    arrowPath.lineCapStyle = .round
    arrowPath.lineJoinStyle = .round
    NSColor.white.setStroke()
    arrowPath.stroke()
    
    // 3. Bottom curved disk dock foot
    let footRect = NSRect(x: driveX + size * 0.08, y: driveY - size * 0.03, width: driveWidth - size * 0.16, height: size * 0.03)
    let footPath = NSBezierPath(roundedRect: footRect, xRadius: size * 0.01, yRadius: size * 0.01)
    NSColor.black.withAlphaComponent(0.25).setFill()
    footPath.fill()
    
    img.unlockFocus()
    return img
}

let fm = FileManager.default
let iconsetDir = URL(fileURLWithPath: "AppIcon.iconset")
try? fm.removeItem(at: iconsetDir)
try fm.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

let iconSizes: [(String, CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, s) in iconSizes {
    let img = createIconImage(size: s)
    if let tiff = img.tiffRepresentation,
       let rep = NSBitmapImageRep(data: tiff),
       let png = rep.representation(using: .png, properties: [:]) {
        let fileURL = iconsetDir.appendingPathComponent(name)
        try png.write(to: fileURL)
    }
}

print("Iconset created successfully")
