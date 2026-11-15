
import AppKit
import CoreGraphics
import UniformTypeIdentifiers

func renderMasterIcon() -> CGImage {
    let size: CGFloat = 1024
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
    guard let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: bitmapInfo) else {
        fatalError("Failed to create CGContext")
    }

    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)

    // 1. Apple-standard macOS Squircle (824x824 centered inside 1024x1024)
    let squircleRect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let cornerRadius: CGFloat = 185

    // Outer Drop Shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -22), blur: 34, color: NSColor.black.withAlphaComponent(0.40).cgColor)
    let squirclePath = CGPath(roundedRect: squircleRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    ctx.addPath(squirclePath)
    ctx.setFillColor(NSColor(red: 0.05, green: 0.08, blue: 0.15, alpha: 1.0).cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // Clip to Squircle
    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.clip()

    // Background Gradient (Deep Midnight Obsidian to Indigo Slate)
    let bgColors = [
        NSColor(red: 0.07, green: 0.12, blue: 0.22, alpha: 1.0).cgColor,
        NSColor(red: 0.02, green: 0.04, blue: 0.09, alpha: 1.0).cgColor
    ] as CFArray
    let bgGradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 1.0])!
    ctx.drawLinearGradient(bgGradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

    // Ambient Center Glow
    ctx.saveGState()
    let glowColors = [
        NSColor(red: 0.08, green: 0.35, blue: 0.65, alpha: 0.35).cgColor,
        NSColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0).cgColor
    ] as CFArray
    let glowGrad = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: [0.0, 1.0])!
    ctx.drawRadialGradient(glowGrad, startCenter: CGPoint(x: 512, y: 512), startRadius: 0, endCenter: CGPoint(x: 512, y: 512), endRadius: 420, options: [])
    ctx.restoreGState()

    // Subtle Digital Grid
    ctx.saveGState()
    ctx.setStrokeColor(NSColor(red: 0.25, green: 0.55, blue: 0.85, alpha: 0.07).cgColor)
    ctx.setLineWidth(1.5)
    for y in stride(from: 100, to: 924, by: 48) {
        ctx.move(to: CGPoint(x: 100, y: CGFloat(y)))
        ctx.addLine(to: CGPoint(x: 924, y: CGFloat(y)))
    }
    for x in stride(from: 100, to: 924, by: 48) {
        ctx.move(to: CGPoint(x: CGFloat(x), y: 100))
        ctx.addLine(to: CGPoint(x: CGFloat(x), y: 924))
    }
    ctx.strokePath()
    ctx.restoreGState()

    // 2. Database Disks (3 Tiers)
    let dbCenterY: CGFloat = 430
    let dbWidth: CGFloat = 500
    let dbHeight: CGFloat = 110
    let dbSpacing: CGFloat = 85

    func drawDisk(yOffset: CGFloat, isTop: Bool) {
        let y = dbCenterY + yOffset
        let rect = CGRect(x: 512 - dbWidth/2, y: y, width: dbWidth, height: dbHeight)

        // Cylinder Body Extrusion
        if !isTop {
            ctx.saveGState()
            let bodyPath = CGMutablePath()
            let depth: CGFloat = 65
            bodyPath.move(to: CGPoint(x: rect.minX, y: rect.midY))
            bodyPath.addLine(to: CGPoint(x: rect.minX, y: rect.midY - depth))
            bodyPath.addCurve(to: CGPoint(x: rect.maxX, y: rect.midY - depth),
                              control1: CGPoint(x: rect.minX + 90, y: rect.minY - depth),
                              control2: CGPoint(x: rect.maxX - 90, y: rect.minY - depth))
            bodyPath.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            bodyPath.addCurve(to: CGPoint(x: rect.minX, y: rect.midY),
                              control1: CGPoint(x: rect.maxX - 90, y: rect.minY),
                              control2: CGPoint(x: rect.minX + 90, y: rect.minY))
            bodyPath.closeSubpath()
            ctx.addPath(bodyPath)
            ctx.clip()

            let bodyColors = [
                NSColor(red: 0.08, green: 0.38, blue: 0.65, alpha: 0.95).cgColor,
                NSColor(red: 0.02, green: 0.18, blue: 0.40, alpha: 0.95).cgColor,
                NSColor(red: 0.10, green: 0.45, blue: 0.75, alpha: 0.95).cgColor
            ] as CFArray
            let bodyGrad = CGGradient(colorsSpace: colorSpace, colors: bodyColors, locations: [0.0, 0.55, 1.0])!
            ctx.drawLinearGradient(bodyGrad, start: CGPoint(x: rect.minX, y: y), end: CGPoint(x: rect.maxX, y: y), options: [])

            // Bottom Rim Highlight
            ctx.restoreGState()
        }

        // Elliptical Top Rim
        ctx.saveGState()
        let rimPath = CGPath(ellipseIn: rect, transform: nil)
        ctx.addPath(rimPath)
        ctx.clip()

        let rimColors = [
            NSColor(red: 0.14, green: 0.58, blue: 0.92, alpha: 0.95).cgColor,
            NSColor(red: 0.05, green: 0.28, blue: 0.55, alpha: 0.95).cgColor
        ] as CFArray
        let rimGrad = CGGradient(colorsSpace: colorSpace, colors: rimColors, locations: [0.0, 1.0])!
        ctx.drawLinearGradient(rimGrad, start: CGPoint(x: 512, y: rect.maxY), end: CGPoint(x: 512, y: rect.minY), options: [])
        ctx.restoreGState()

        // Rim Border Stroke
        ctx.saveGState()
        ctx.addPath(rimPath)
        ctx.setStrokeColor(NSColor(red: 0.45, green: 0.85, blue: 1.0, alpha: 0.7).cgColor)
        ctx.setLineWidth(3.0)
        ctx.strokePath()
        ctx.restoreGState()
    }

    drawDisk(yOffset: -dbSpacing, isTop: false)
    drawDisk(yOffset: 0, isTop: false)
    drawDisk(yOffset: dbSpacing, isTop: true)

    // 3. "千里眼" Clairvoyant Aperture / Glowing Eye Motif (Centered around y = 560)
    let eyeCenter = CGPoint(x: 512, y: 550)

    // 3.1 Horizon Scanning Light Beam
    ctx.saveGState()
    let beamRect = CGRect(x: 180, y: eyeCenter.y - 2, width: 664, height: 4)
    let beamColors = [
        NSColor(red: 0.2, green: 0.8, blue: 1.0, alpha: 0.0).cgColor,
        NSColor(red: 0.4, green: 0.95, blue: 1.0, alpha: 0.85).cgColor,
        NSColor(red: 0.2, green: 0.8, blue: 1.0, alpha: 0.0).cgColor
    ] as CFArray
    let beamGrad = CGGradient(colorsSpace: colorSpace, colors: beamColors, locations: [0.0, 0.5, 1.0])!
    ctx.drawLinearGradient(beamGrad, start: CGPoint(x: beamRect.minX, y: eyeCenter.y), end: CGPoint(x: beamRect.maxX, y: eyeCenter.y), options: [])
    ctx.restoreGState()

    // 3.2 Eye Outer Neon Glow
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 50, color: NSColor(red: 0.15, green: 0.85, blue: 1.0, alpha: 0.95).cgColor)
    let eyePath = CGMutablePath()
    let eyeW: CGFloat = 220
    let eyeH: CGFloat = 115
    eyePath.move(to: CGPoint(x: eyeCenter.x - eyeW, y: eyeCenter.y))
    eyePath.addCurve(to: CGPoint(x: eyeCenter.x + eyeW, y: eyeCenter.y),
                     control1: CGPoint(x: eyeCenter.x - 75, y: eyeCenter.y + eyeH),
                     control2: CGPoint(x: eyeCenter.x + 75, y: eyeCenter.y + eyeH))
    eyePath.addCurve(to: CGPoint(x: eyeCenter.x - eyeW, y: eyeCenter.y),
                     control1: CGPoint(x: eyeCenter.x + 75, y: eyeCenter.y - eyeH),
                     control2: CGPoint(x: eyeCenter.x - 75, y: eyeCenter.y - eyeH))
    eyePath.closeSubpath()

    // Fill eye background with subtle translucent dark glass
    ctx.addPath(eyePath)
    ctx.setFillColor(NSColor(red: 0.03, green: 0.08, blue: 0.18, alpha: 0.75).cgColor)
    ctx.fillPath()

    // Stroke the eye contour
    ctx.addPath(eyePath)
    ctx.setStrokeColor(NSColor(red: 0.65, green: 0.92, blue: 1.0, alpha: 1.0).cgColor)
    ctx.setLineWidth(7.0)
    ctx.strokePath()
    ctx.restoreGState()

    // 3.3 Iris (Electric Azure Radial Glow)
    ctx.saveGState()
    ctx.addArc(center: eyeCenter, radius: 68, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.clip()
    let irisColors = [
        NSColor(red: 0.25, green: 0.88, blue: 1.0, alpha: 1.0).cgColor,
        NSColor(red: 0.06, green: 0.35, blue: 0.75, alpha: 1.0).cgColor
    ] as CFArray
    let irisGrad = CGGradient(colorsSpace: colorSpace, colors: irisColors, locations: [0.0, 1.0])!
    ctx.drawRadialGradient(irisGrad, startCenter: eyeCenter, startRadius: 0, endCenter: eyeCenter, endRadius: 68, options: [])
    ctx.restoreGState()

    // 3.4 Golden Pupil (Focus of Clairvoyance)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 24, color: NSColor(red: 1.0, green: 0.8, blue: 0.2, alpha: 0.95).cgColor)
    ctx.addArc(center: eyeCenter, radius: 28, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.setFillColor(NSColor(red: 1.0, green: 0.92, blue: 0.50, alpha: 1.0).cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // 3.5 Specular Spark
    ctx.saveGState()
    ctx.addArc(center: CGPoint(x: eyeCenter.x - 14, y: eyeCenter.y + 15), radius: 8, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.setFillColor(NSColor.white.withAlphaComponent(0.95).cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // 4. Subtle Inner Highlight on Squircle Bevel
    ctx.saveGState()
    let innerBevelPath = CGPath(roundedRect: squircleRect.insetBy(dx: 1.5, dy: 1.5), cornerWidth: cornerRadius - 1.5, cornerHeight: cornerRadius - 1.5, transform: nil)
    ctx.addPath(innerBevelPath)
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.20).cgColor)
    ctx.setLineWidth(3)
    ctx.strokePath()
    ctx.restoreGState()

    ctx.restoreGState() // Close squircle clip

    return ctx.makeImage()!
}

func savePNG(image: CGImage, to url: URL, targetSize: Int) {
    let rep = NSBitmapImageRep(cgImage: image)
    let resized = NSImage(size: NSSize(width: targetSize, height: targetSize))
    resized.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    rep.draw(in: NSRect(x: 0, y: 0, width: targetSize, height: targetSize))
    resized.unlockFocus()

    guard let tiff = resized.tiffRepresentation,
          let resizedRep = NSBitmapImageRep(data: tiff),
          let pngData = resizedRep.representation(using: .png, properties: [:]) else {
        fatalError("Failed to convert to PNG")
    }
    try! pngData.write(to: url)
}

let fm = FileManager.default
let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let rootDir = scriptDir.deletingLastPathComponent()
let iconsetDir = rootDir.appendingPathComponent("AppIcon.iconset")
let resourcesDir = rootDir.appendingPathComponent("resources")
let icnsPath = resourcesDir.appendingPathComponent("AppIcon.icns")

try? fm.createDirectory(at: iconsetDir, withIntermediateDirectories: true)
try? fm.createDirectory(at: resourcesDir, withIntermediateDirectories: true)

print("==> Generating 1024x1024 Master Icon...")
let master = renderMasterIcon()

let specs: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for (name, size) in specs {
    let fileUrl = iconsetDir.appendingPathComponent(name)
    savePNG(image: master, to: fileUrl, targetSize: size)
}

print("==> Running iconutil to generate AppIcon.icns...")
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetDir.path, "-o", icnsPath.path]
try! process.run()
process.waitUntilExit()

if process.terminationStatus == 0 {
    print("==> Success! Created: \(icnsPath.path)")
    try? fm.removeItem(at: iconsetDir)
} else {
    fatalError("iconutil failed with code \(process.terminationStatus)")
}
