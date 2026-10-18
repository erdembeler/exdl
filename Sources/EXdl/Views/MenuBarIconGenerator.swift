import AppKit
import SwiftUI

enum MenuBarIconStyle: Int, CaseIterable, Identifiable {
    case minimalSSDArrow = 1
    case verticalNVMe = 2
    case exMonogram = 3
    case solidPerspectiveDrive = 4
    case dualStackedDrives = 5
    case appDockingCradle = 6
    case thunderboltCapsule = 7
    case isometricCube = 8
    case diskPlatterArrow = 9
    case cleanOutlinedDrive = 10

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .minimalSSDArrow: return tr("1. Minimal SSD & Arrow")
        case .verticalNVMe: return tr("2. Portable NVMe & USB-C")
        case .exMonogram: return tr("3. EX Monogram Badge")
        case .solidPerspectiveDrive: return tr("4. Solid Perspective Drive")
        case .dualStackedDrives: return tr("5. Dual Stacked Drives")
        case .appDockingCradle: return tr("6. App & Drive Dock")
        case .thunderboltCapsule: return tr("7. High-Speed NVMe Pill")
        case .isometricCube: return tr("8. Isometric 3D Block")
        case .diskPlatterArrow: return tr("9. Disk Ring & Arrow")
        case .cleanOutlinedDrive: return tr("10. Clean Outlined Drive")
        }
    }
}

enum MenuBarIconGenerator {
    /// Generates a Retina-sharp `isTemplate = true` `NSImage` for the macOS Menu Bar.
    /// When `isMonitoringEnabled` is `true`, the icon is drawn filled (içi dolu).
    /// When `isMonitoringEnabled` is `false`, the icon is drawn hollow/outlined (içi boş) at full crispness.
    static func image(
        style: MenuBarIconStyle,
        isMonitoringEnabled: Bool = true,
        hasPendingPrompt: Bool = false,
        pointSize: CGFloat = 18
    ) -> NSImage {
        let size = NSSize(width: pointSize, height: pointSize)
        let image = NSImage(size: size, flipped: false) { rect in
            let drawColor = NSColor.black
            drawIcon(style: style, in: rect, color: drawColor, isFilled: isMonitoringEnabled)

            if hasPendingPrompt {
                guard let ctx = NSGraphicsContext.current?.cgContext else { return true }
                ctx.saveGState()
                let u = min(rect.width, rect.height) / 18.0
                let dotRect = CGRect(x: rect.maxX - 4.8 * u, y: rect.maxY - 4.8 * u, width: 4.2 * u, height: 4.2 * u)
                ctx.setBlendMode(.clear)
                NSBezierPath(ovalIn: dotRect.insetBy(dx: -0.9 * u, dy: -0.9 * u)).fill()
                ctx.setBlendMode(.normal)
                NSColor.black.setFill()
                NSBezierPath(ovalIn: dotRect).fill()
                ctx.restoreGState()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    static func drawIcon(style: MenuBarIconStyle, in rect: NSRect, color: NSColor, isFilled: Bool = true) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        defer { ctx.restoreGState() }

        let s = min(rect.width, rect.height)
        let ox = rect.minX + (rect.width - s) / 2
        let oy = rect.minY + (rect.height - s) / 2
        let u = s / 18.0

        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: ox + x * u, y: oy + y * u)
        }
        func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(x: ox + x * u, y: oy + y * u, width: w * u, height: h * u)
        }

        color.setFill()
        color.setStroke()
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        switch style {
        case .minimalSSDArrow:
            if isFilled {
                ctx.beginTransparencyLayer(auxiliaryInfo: nil)
                let base = NSBezierPath(roundedRect: r(1.6, 2.0, 14.8, 6.4), xRadius: 1.9 * u, yRadius: 1.9 * u)
                base.fill()
                ctx.setBlendMode(.clear)
                NSBezierPath(ovalIn: r(12.6, 4.2, 2.0, 2.0)).fill()
                NSBezierPath(roundedRect: r(3.6, 4.5, 5.4, 1.5), xRadius: 0.75 * u, yRadius: 0.75 * u).fill()
                ctx.setBlendMode(.normal)
                ctx.endTransparencyLayer()
            } else {
                let basePath = NSBezierPath()
                basePath.lineWidth = 1.6 * u
                basePath.move(to: p(5.2, 8.4))
                basePath.line(to: p(3.2, 8.4))
                basePath.curve(to: p(1.8, 7.0), controlPoint1: p(2.4, 8.4), controlPoint2: p(1.8, 7.8))
                basePath.line(to: p(1.8, 3.6))
                basePath.curve(to: p(3.2, 2.2), controlPoint1: p(1.8, 2.8), controlPoint2: p(2.4, 2.2))
                basePath.line(to: p(14.8, 2.2))
                basePath.curve(to: p(16.2, 3.6), controlPoint1: p(15.6, 2.2), controlPoint2: p(16.2, 2.8))
                basePath.line(to: p(16.2, 7.0))
                basePath.curve(to: p(14.8, 8.4), controlPoint1: p(16.2, 7.8), controlPoint2: p(15.6, 8.4))
                basePath.line(to: p(12.8, 8.4))
                basePath.stroke()
                NSBezierPath(ovalIn: r(12.6, 4.3, 1.8, 1.8)).fill()
                NSBezierPath(roundedRect: r(3.8, 4.5, 5.0, 1.4), xRadius: 0.7 * u, yRadius: 0.7 * u).fill()
            }

            let arrow = NSBezierPath()
            arrow.lineWidth = 1.8 * u
            arrow.move(to: p(9.0, 16.0))
            arrow.line(to: p(9.0, 9.2))
            arrow.move(to: p(6.2, 11.7))
            arrow.line(to: p(9.0, 8.9))
            arrow.line(to: p(11.8, 11.7))
            arrow.stroke()

        case .verticalNVMe:
            let body = NSBezierPath(roundedRect: r(3.6, 3.4, 10.8, 13.0), xRadius: 2.8 * u, yRadius: 2.8 * u)
            let port = NSBezierPath(roundedRect: r(6.8, 1.2, 4.4, 2.2), xRadius: 0.8 * u, yRadius: 0.8 * u)
            let arrow = NSBezierPath()
            arrow.lineWidth = 1.7 * u
            arrow.move(to: p(9.0, 13.4))
            arrow.line(to: p(9.0, 6.8))
            arrow.move(to: p(6.4, 9.2))
            arrow.line(to: p(9.0, 6.5))
            arrow.line(to: p(11.6, 9.2))

            if isFilled {
                ctx.beginTransparencyLayer(auxiliaryInfo: nil)
                body.fill()
                port.fill()
                ctx.setBlendMode(.clear)
                arrow.stroke()
                ctx.setBlendMode(.normal)
                ctx.endTransparencyLayer()
            } else {
                body.lineWidth = 1.6 * u
                body.stroke()
                port.lineWidth = 1.4 * u
                port.stroke()
                arrow.stroke()
            }

        case .exMonogram:
            let badge = NSBezierPath(roundedRect: r(1.2, 3.0, 15.6, 12.0), xRadius: 2.8 * u, yRadius: 2.8 * u)

            let ePath = NSBezierPath()
            ePath.lineWidth = 1.7 * u
            ePath.move(to: p(7.5, 11.8))
            ePath.line(to: p(4.3, 11.8))
            ePath.line(to: p(4.3, 6.2))
            ePath.line(to: p(7.5, 6.2))
            ePath.move(to: p(4.3, 9.0))
            ePath.line(to: p(6.9, 9.0))

            let xPath = NSBezierPath()
            xPath.lineWidth = 1.7 * u
            xPath.move(to: p(9.8, 11.8))
            xPath.line(to: p(13.6, 6.2))
            xPath.move(to: p(13.6, 11.8))
            xPath.line(to: p(9.8, 6.2))

            if isFilled {
                ctx.beginTransparencyLayer(auxiliaryInfo: nil)
                badge.fill()
                ctx.setBlendMode(.clear)
                ePath.stroke()
                xPath.stroke()
                ctx.setBlendMode(.normal)
                ctx.endTransparencyLayer()
            } else {
                badge.lineWidth = 1.6 * u
                badge.stroke()
                ePath.stroke()
                xPath.stroke()
            }

        case .solidPerspectiveDrive:
            let hull = NSBezierPath()
            hull.move(to: p(3.8, 14.5))
            hull.line(to: p(14.2, 14.5))
            hull.curve(to: p(15.6, 13.4), controlPoint1: p(14.9, 14.5), controlPoint2: p(15.4, 14.0))
            hull.line(to: p(16.8, 7.6))
            hull.line(to: p(16.8, 4.2))
            hull.curve(to: p(15.0, 2.4), controlPoint1: p(16.8, 3.1), controlPoint2: p(16.0, 2.4))
            hull.line(to: p(3.0, 2.4))
            hull.curve(to: p(1.2, 4.2), controlPoint1: p(2.0, 2.4), controlPoint2: p(1.2, 3.1))
            hull.line(to: p(1.2, 7.6))
            hull.line(to: p(2.4, 13.4))
            hull.curve(to: p(3.8, 14.5), controlPoint1: p(2.6, 14.0), controlPoint2: p(3.1, 14.5))
            hull.close()

            let arrowCut = NSBezierPath()
            arrowCut.lineWidth = 1.7 * u
            arrowCut.move(to: p(9.0, 13.0))
            arrowCut.line(to: p(9.0, 8.8))
            arrowCut.move(to: p(6.7, 10.6))
            arrowCut.line(to: p(9.0, 8.5))
            arrowCut.line(to: p(11.3, 10.6))

            if isFilled {
                ctx.beginTransparencyLayer(auxiliaryInfo: nil)
                hull.fill()
                ctx.setBlendMode(.clear)
                NSBezierPath(roundedRect: r(2.6, 3.7, 12.8, 3.4), xRadius: 1.2 * u, yRadius: 1.2 * u).fill()
                arrowCut.stroke()
                ctx.setBlendMode(.normal)
                NSBezierPath(ovalIn: r(12.4, 4.5, 1.8, 1.8)).fill()
                NSBezierPath(roundedRect: r(3.8, 4.7, 4.6, 1.4), xRadius: 0.7 * u, yRadius: 0.7 * u).fill()
                ctx.endTransparencyLayer()
            } else {
                hull.lineWidth = 1.6 * u
                hull.stroke()
                let seam = NSBezierPath()
                seam.lineWidth = 1.4 * u
                seam.move(to: p(1.4, 7.2))
                seam.line(to: p(16.6, 7.2))
                seam.stroke()
                arrowCut.stroke()
                NSBezierPath(ovalIn: r(12.4, 4.0, 1.7, 1.7)).fill()
                NSBezierPath(roundedRect: r(3.8, 4.2, 4.6, 1.3), xRadius: 0.65 * u, yRadius: 0.65 * u).fill()
            }

        case .dualStackedDrives:
            let topBar = NSBezierPath(roundedRect: r(3.0, 12.0, 12.0, 3.8), xRadius: 1.4 * u, yRadius: 1.4 * u)
            let botBar = NSBezierPath(roundedRect: r(1.6, 2.0, 14.8, 5.2), xRadius: 1.8 * u, yRadius: 1.8 * u)

            if isFilled {
                ctx.beginTransparencyLayer(auxiliaryInfo: nil)
                topBar.fill()
                botBar.fill()
                ctx.setBlendMode(.clear)
                NSBezierPath(ovalIn: r(12.2, 13.1, 1.6, 1.6)).fill()
                NSBezierPath(ovalIn: r(13.0, 3.7, 1.8, 1.8)).fill()
                NSBezierPath(roundedRect: r(3.4, 3.9, 5.0, 1.4), xRadius: 0.7 * u, yRadius: 0.7 * u).fill()
                ctx.setBlendMode(.normal)
                ctx.endTransparencyLayer()
            } else {
                topBar.lineWidth = 1.5 * u
                topBar.stroke()
                NSBezierPath(ovalIn: r(12.2, 13.1, 1.5, 1.5)).fill()

                botBar.lineWidth = 1.6 * u
                botBar.stroke()
                NSBezierPath(ovalIn: r(13.0, 3.7, 1.7, 1.7)).fill()
                NSBezierPath(roundedRect: r(3.4, 3.9, 5.0, 1.4), xRadius: 0.7 * u, yRadius: 0.7 * u).fill()
            }

            let chev = NSBezierPath()
            chev.lineWidth = 1.65 * u
            chev.move(to: p(6.8, 10.3))
            chev.line(to: p(9.0, 8.2))
            chev.line(to: p(11.2, 10.3))
            chev.stroke()

        case .appDockingCradle:
            let appBox = NSBezierPath(roundedRect: r(5.3, 8.8, 7.4, 7.2), xRadius: 2.0 * u, yRadius: 2.0 * u)
            let miniArr = NSBezierPath()
            miniArr.lineWidth = 1.5 * u
            miniArr.move(to: p(9.0, 14.0))
            miniArr.line(to: p(9.0, 10.6))
            miniArr.move(to: p(7.4, 12.0))
            miniArr.line(to: p(9.0, 10.4))
            miniArr.line(to: p(10.6, 12.0))

            let cradle = NSBezierPath(roundedRect: r(1.8, 2.0, 14.4, 4.6), xRadius: 1.8 * u, yRadius: 1.8 * u)

            if isFilled {
                ctx.beginTransparencyLayer(auxiliaryInfo: nil)
                appBox.fill()
                cradle.fill()
                ctx.setBlendMode(.clear)
                miniArr.stroke()
                NSBezierPath(ovalIn: r(13.0, 3.5, 1.6, 1.6)).fill()
                NSBezierPath(roundedRect: r(3.6, 3.6, 4.5, 1.4), xRadius: 0.7 * u, yRadius: 0.7 * u).fill()
                ctx.setBlendMode(.normal)
                ctx.endTransparencyLayer()
            } else {
                appBox.lineWidth = 1.6 * u
                appBox.stroke()
                miniArr.stroke()
                cradle.lineWidth = 1.6 * u
                cradle.stroke()
                NSBezierPath(ovalIn: r(13.0, 3.5, 1.6, 1.6)).fill()
                NSBezierPath(roundedRect: r(3.6, 3.6, 4.5, 1.4), xRadius: 0.7 * u, yRadius: 0.7 * u).fill()
            }

        case .thunderboltCapsule:
            let pill = NSBezierPath(roundedRect: r(1.4, 4.4, 15.2, 9.2), xRadius: 4.6 * u, yRadius: 4.6 * u)
            let bolt = NSBezierPath()
            bolt.move(to: p(9.8, 12.2))
            bolt.line(to: p(6.6, 8.8))
            bolt.line(to: p(9.1, 8.8))
            bolt.line(to: p(8.2, 5.8))
            bolt.line(to: p(11.4, 9.2))
            bolt.line(to: p(8.9, 9.2))
            bolt.close()

            if isFilled {
                ctx.beginTransparencyLayer(auxiliaryInfo: nil)
                pill.fill()
                ctx.setBlendMode(.clear)
                bolt.fill()
                ctx.setBlendMode(.normal)
                ctx.endTransparencyLayer()
            } else {
                pill.lineWidth = 1.65 * u
                pill.stroke()
                bolt.fill()
            }

        case .isometricCube:
            let cube = NSBezierPath()
            cube.move(to: p(9.0, 1.8))
            cube.line(to: p(15.8, 5.2))
            cube.line(to: p(15.8, 10.2))
            cube.line(to: p(9.0, 6.8))
            cube.line(to: p(2.2, 10.2))
            cube.line(to: p(2.2, 5.2))
            cube.close()

            let centerLine = NSBezierPath()
            centerLine.lineWidth = 1.55 * u
            centerLine.move(to: p(9.0, 1.8))
            centerLine.line(to: p(9.0, 6.8))

            if isFilled {
                ctx.beginTransparencyLayer(auxiliaryInfo: nil)
                cube.fill()
                ctx.setBlendMode(.clear)
                centerLine.stroke()
                ctx.setBlendMode(.normal)
                ctx.endTransparencyLayer()
            } else {
                cube.lineWidth = 1.55 * u
                cube.stroke()
                centerLine.stroke()
            }

            let drop = NSBezierPath()
            drop.lineWidth = 1.8 * u
            drop.move(to: p(9.0, 16.4))
            drop.line(to: p(9.0, 9.8))
            drop.move(to: p(6.3, 12.3))
            drop.line(to: p(9.0, 9.5))
            drop.line(to: p(11.7, 12.3))
            drop.stroke()

        case .diskPlatterArrow:
            let outArr = NSBezierPath()
            outArr.lineWidth = 1.75 * u
            outArr.move(to: p(6.2, 9.0))
            outArr.line(to: p(15.8, 9.0))
            outArr.move(to: p(12.6, 6.0))
            outArr.line(to: p(15.8, 9.0))
            outArr.line(to: p(12.6, 12.0))

            if isFilled {
                ctx.beginTransparencyLayer(auxiliaryInfo: nil)
                NSBezierPath(ovalIn: r(1.8, 1.8, 14.4, 14.4)).fill()
                ctx.setBlendMode(.clear)
                outArr.stroke()
                NSBezierPath(ovalIn: r(4.0, 7.8, 2.4, 2.4)).fill()
                ctx.setBlendMode(.normal)
                ctx.endTransparencyLayer()
            } else {
                let ring = NSBezierPath()
                ring.lineWidth = 1.65 * u
                ring.appendArc(withCenter: p(9.0, 9.0), radius: 6.8 * u, startAngle: 45, endAngle: 315, clockwise: false)
                ring.stroke()
                outArr.stroke()
                NSBezierPath(ovalIn: r(4.2, 7.9, 2.2, 2.2)).fill()
            }

        case .cleanOutlinedDrive:
            let front = NSBezierPath(roundedRect: r(1.6, 2.6, 14.8, 5.2), xRadius: 1.8 * u, yRadius: 1.8 * u)
            let topRoof = NSBezierPath()
            topRoof.move(to: p(1.8, 7.0))
            topRoof.line(to: p(3.6, 14.0))
            topRoof.curve(to: p(5.0, 15.0), controlPoint1: p(3.8, 14.6), controlPoint2: p(4.3, 15.0))
            topRoof.line(to: p(13.0, 15.0))
            topRoof.curve(to: p(14.4, 14.0), controlPoint1: p(13.7, 15.0), controlPoint2: p(14.2, 14.6))
            topRoof.line(to: p(16.2, 7.0))

            if isFilled {
                ctx.beginTransparencyLayer(auxiliaryInfo: nil)
                topRoof.close()
                topRoof.fill()
                front.fill()
                ctx.setBlendMode(.clear)
                let seam = NSBezierPath(roundedRect: r(1.2, 7.0, 15.6, 1.3), xRadius: 0.6 * u, yRadius: 0.6 * u)
                seam.fill()
                NSBezierPath(ovalIn: r(13.0, 4.3, 1.8, 1.8)).fill()
                NSBezierPath(roundedRect: r(3.6, 4.5, 5.2, 1.4), xRadius: 0.7 * u, yRadius: 0.7 * u).fill()
                ctx.setBlendMode(.normal)
                ctx.endTransparencyLayer()
            } else {
                front.lineWidth = 1.6 * u
                front.stroke()
                topRoof.lineWidth = 1.6 * u
                topRoof.stroke()
                NSBezierPath(ovalIn: r(13.0, 4.3, 1.8, 1.8)).fill()
                NSBezierPath(roundedRect: r(3.6, 4.5, 5.2, 1.4), xRadius: 0.7 * u, yRadius: 0.7 * u).fill()
            }
        }
    }
}
