import AppKit
import CoreGraphics
import Foundation

guard CommandLine.arguments.count >= 2 else {
    fputs("Usage: generate_icon.swift <output.iconset>\n", stderr)
    exit(1)
}

let outputDir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

func drawIcon(pixelSize: Int) -> Data? {
    let s = CGFloat(pixelSize)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        return nil
    }

    guard let nsCtx = NSGraphicsContext(bitmapImageRep: rep) else {
        return nil
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = nsCtx
    let ctx = nsCtx.cgContext
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    let colorSpace = CGColorSpaceCreateDeviceRGB()

    // macOS icon safe inset & squircle-like rounded rect
    let inset = s * 0.095
    let cardRect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let cornerRadius = cardRect.width * 0.225
    let bgPath = CGPath(
        roundedRect: cardRect,
        cornerWidth: cornerRadius,
        cornerHeight: cornerRadius,
        transform: nil
    )

    // Soft ambient shadow behind app tile
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -s * 0.025),
        blur: s * 0.045,
        color: CGColor(red: 0.04, green: 0.08, blue: 0.22, alpha: 0.42)
    )
    ctx.addPath(bgPath)
    ctx.setFillColor(CGColor(red: 0.12, green: 0.28, blue: 0.68, alpha: 1.0))
    ctx.fillPath()
    ctx.restoreGState()

    // Clip to rounded square background
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()

    // Rich diagonal sapphire-to-sky gradient
    let bgColors = [
        CGColor(red: 0.09, green: 0.16, blue: 0.44, alpha: 1.0),
        CGColor(red: 0.16, green: 0.37, blue: 0.85, alpha: 1.0),
        CGColor(red: 0.20, green: 0.64, blue: 0.96, alpha: 1.0)
    ] as CFArray
    if let bgGradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 0.55, 1.0]) {
        ctx.drawLinearGradient(
            bgGradient,
            start: CGPoint(x: cardRect.minX, y: cardRect.minY),
            end: CGPoint(x: cardRect.maxX, y: cardRect.maxY),
            options: []
        )
    }

    // Subtle radial top-left glow
    let glowColors = [
        CGColor(red: 0.65, green: 0.90, blue: 1.0, alpha: 0.32),
        CGColor(red: 0.65, green: 0.90, blue: 1.0, alpha: 0.0)
    ] as CFArray
    if let glowGrad = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: [0.0, 1.0]) {
        let center = CGPoint(x: cardRect.minX + cardRect.width * 0.32, y: cardRect.maxY - cardRect.height * 0.20)
        ctx.drawRadialGradient(
            glowGrad,
            startCenter: center,
            startRadius: 0,
            endCenter: center,
            endRadius: cardRect.width * 0.68,
            options: []
        )
    }

    // Stacked floating file cards (back left, back right, front center)
    func drawFloatingCard(centerX: CGFloat, centerY: CGFloat, w: CGFloat, h: CGFloat, angleDeg: CGFloat, alpha: CGFloat, drawDetails: Bool) {
        ctx.saveGState()
        ctx.translateBy(x: centerX, y: centerY)
        ctx.rotate(by: angleDeg * .pi / 180.0)

        let rect = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
        let r = w * 0.16
        let path = CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)

        ctx.setShadow(
            offset: CGSize(width: 0, height: -s * 0.015),
            blur: s * 0.032,
            color: CGColor(red: 0.03, green: 0.09, blue: 0.28, alpha: 0.32)
        )
        ctx.addPath(path)
        ctx.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: alpha))
        ctx.fillPath()

        if drawDetails {
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
            // Downward drop arrow inside the front card
            let arrowColor = CGColor(red: 0.14, green: 0.42, blue: 0.90, alpha: 0.95)
            ctx.setStrokeColor(arrowColor)
            ctx.setLineWidth(max(1.5, s * 0.036))
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)

            let shaftTop = h * 0.24
            let shaftBottom = -h * 0.18
            ctx.move(to: CGPoint(x: 0, y: shaftTop))
            ctx.addLine(to: CGPoint(x: 0, y: shaftBottom))
            ctx.strokePath()

            let headW = w * 0.24
            let headY = shaftBottom + h * 0.18
            ctx.move(to: CGPoint(x: -headW, y: headY))
            ctx.addLine(to: CGPoint(x: 0, y: shaftBottom))
            ctx.addLine(to: CGPoint(x: headW, y: headY))
            ctx.strokePath()
        }

        ctx.restoreGState()
    }

    let cw = cardRect.width
    let ch = cardRect.height

    // Back-left translucent card
    drawFloatingCard(
        centerX: cardRect.midX - cw * 0.15,
        centerY: cardRect.midY + ch * 0.12,
        w: cw * 0.36,
        h: ch * 0.40,
        angleDeg: 11,
        alpha: 0.46,
        drawDetails: false
    )

    // Back-right translucent card
    drawFloatingCard(
        centerX: cardRect.midX + cw * 0.15,
        centerY: cardRect.midY + ch * 0.12,
        w: cw * 0.36,
        h: ch * 0.40,
        angleDeg: -11,
        alpha: 0.62,
        drawDetails: false
    )

    // Front crisp white card with downward drop chevron
    drawFloatingCard(
        centerX: cardRect.midX,
        centerY: cardRect.midY + ch * 0.14,
        w: cw * 0.42,
        h: ch * 0.44,
        angleDeg: 0,
        alpha: 0.97,
        drawDetails: true
    )

    // Foreground frosted shelf tray at lower portion
    let trayW = cw * 0.72
    let trayH = ch * 0.28
    let trayRect = CGRect(
        x: cardRect.midX - trayW / 2,
        y: cardRect.minY + ch * 0.12,
        width: trayW,
        height: trayH
    )
    let trayRadius = trayH * 0.36
    let trayPath = CGPath(
        roundedRect: trayRect,
        cornerWidth: trayRadius,
        cornerHeight: trayRadius,
        transform: nil
    )

    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -s * 0.014),
        blur: s * 0.028,
        color: CGColor(red: 0.03, green: 0.08, blue: 0.24, alpha: 0.38)
    )
    ctx.addPath(trayPath)
    ctx.setFillColor(CGColor(red: 0.92, green: 0.97, blue: 1.0, alpha: 0.26))
    ctx.fillPath()
    ctx.restoreGState()

    // Tray bright top rim & glass highlight
    ctx.saveGState()
    ctx.addPath(trayPath)
    ctx.clip()
    let trayColors = [
        CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.18),
        CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.44)
    ] as CFArray
    if let trayGrad = CGGradient(colorsSpace: colorSpace, colors: trayColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(
            trayGrad,
            start: CGPoint(x: trayRect.midX, y: trayRect.minY),
            end: CGPoint(x: trayRect.midX, y: trayRect.maxY),
            options: []
        )
    }
    ctx.restoreGState()

    ctx.addPath(trayPath)
    ctx.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.65))
    ctx.setLineWidth(max(1.0, s * 0.012))
    ctx.strokePath()

    // Subtle pill handle inside tray
    let handleW = trayW * 0.28
    let handleH = max(1.5, trayH * 0.16)
    let handleRect = CGRect(
        x: trayRect.midX - handleW / 2,
        y: trayRect.midY - handleH / 2,
        width: handleW,
        height: handleH
    )
    let handlePath = CGPath(
        roundedRect: handleRect,
        cornerWidth: handleH / 2,
        cornerHeight: handleH / 2,
        transform: nil
    )
    ctx.addPath(handlePath)
    ctx.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.88))
    ctx.fillPath()

    // Crisp inner rim around app tile
    ctx.addPath(bgPath)
    ctx.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.24))
    ctx.setLineWidth(max(1.0, s * 0.012))
    ctx.strokePath()

    ctx.restoreGState()
    NSGraphicsContext.restoreGraphicsState()

    return rep.representation(using: .png, properties: [:])
}

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
    ("icon_512x512@2x.png", 1024)
]

for (filename, size) in specs {
    guard let data = drawIcon(pixelSize: size) else {
        fputs("Failed to render \(filename)\n", stderr)
        exit(1)
    }
    try data.write(to: outputDir.appendingPathComponent(filename))
}
