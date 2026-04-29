import AppKit
import CoreGraphics
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let appIconDirectory = root
    .appending(path: "ios")
    .appending(path: "PrivateMoments")
    .appending(path: "Assets.xcassets")
    .appending(path: "AppIcon.appiconset")

try FileManager.default.createDirectory(at: appIconDirectory, withIntermediateDirectories: true)

struct IconImage {
    let idiom: String
    let size: String
    let scale: String
    let filename: String
    let pixels: Int
}

let images = [
    IconImage(idiom: "iphone", size: "20x20", scale: "2x", filename: "Icon-App-20x20@2x.png", pixels: 40),
    IconImage(idiom: "iphone", size: "20x20", scale: "3x", filename: "Icon-App-20x20@3x.png", pixels: 60),
    IconImage(idiom: "iphone", size: "29x29", scale: "2x", filename: "Icon-App-29x29@2x.png", pixels: 58),
    IconImage(idiom: "iphone", size: "29x29", scale: "3x", filename: "Icon-App-29x29@3x.png", pixels: 87),
    IconImage(idiom: "iphone", size: "40x40", scale: "2x", filename: "Icon-App-40x40@2x.png", pixels: 80),
    IconImage(idiom: "iphone", size: "40x40", scale: "3x", filename: "Icon-App-40x40@3x.png", pixels: 120),
    IconImage(idiom: "iphone", size: "60x60", scale: "2x", filename: "Icon-App-60x60@2x.png", pixels: 120),
    IconImage(idiom: "iphone", size: "60x60", scale: "3x", filename: "Icon-App-60x60@3x.png", pixels: 180),
    IconImage(idiom: "ios-marketing", size: "1024x1024", scale: "1x", filename: "Icon-App-1024x1024@1x.png", pixels: 1024)
]

for image in images {
    let icon = drawIcon(size: image.pixels)
    let output = appIconDirectory.appending(path: image.filename)
    try writePNG(icon, to: output)
}

let contents: [String: Any] = [
    "images": images.map { image in
        [
            "idiom": image.idiom,
            "size": image.size,
            "scale": image.scale,
            "filename": image.filename
        ]
    },
    "info": [
        "author": "xcode",
        "version": 1
    ]
]

let data = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try data.write(to: appIconDirectory.appending(path: "Contents.json"))

let assetContents: [String: Any] = [
    "info": [
        "author": "xcode",
        "version": 1
    ]
]
let assetDirectory = appIconDirectory.deletingLastPathComponent()
let assetData = try JSONSerialization.data(withJSONObject: assetContents, options: [.prettyPrinted, .sortedKeys])
try assetData.write(to: assetDirectory.appending(path: "Contents.json"))

func drawIcon(size: Int) -> CGImage {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    ) else {
        fatalError("Unable to create drawing context")
    }

    let canvas = CGFloat(size)
    let scale = canvas / 1024

    context.saveGState()
    context.translateBy(x: 0, y: canvas)
    context.scaleBy(x: scale, y: -scale)
    drawBase(in: context)
    drawGradientRing(in: context)
    drawFace(in: context)
    context.restoreGState()

    guard let image = context.makeImage() else {
        fatalError("Unable to create icon image")
    }

    return image
}

func drawBase(in context: CGContext) {
    let rect = CGRect(x: 0, y: 0, width: 1024, height: 1024)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let colors = [
        NSColor(calibratedWhite: 1, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.965, green: 0.978, blue: 0.985, alpha: 1).cgColor
    ] as CFArray

    context.setFillColor(NSColor.white.cgColor)
    context.fill(rect)

    if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 1]) {
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: 180, y: 60),
            end: CGPoint(x: 850, y: 980),
            options: []
        )
    }
}

func drawGradientRing(in context: CGContext) {
    let center = CGPoint(x: 512, y: 515)
    let radius: CGFloat = 315
    let lineWidth: CGFloat = 88
    let startDegrees: CGFloat = 98
    let endDegrees: CGFloat = 420
    let segments = 300

    context.setLineWidth(lineWidth)
    context.setLineCap(.round)
    context.setLineJoin(.round)

    for index in 0..<segments {
        let t0 = CGFloat(index) / CGFloat(segments)
        let t1 = CGFloat(index + 1) / CGFloat(segments)
        let a0 = (startDegrees + (endDegrees - startDegrees) * t0) * .pi / 180
        let a1 = (startDegrees + (endDegrees - startDegrees) * t1) * .pi / 180
        let p0 = CGPoint(x: center.x + radius * cos(a0), y: center.y + radius * sin(a0))
        let p1 = CGPoint(x: center.x + radius * cos(a1), y: center.y + radius * sin(a1))

        context.setStrokeColor(gradientColor(t: (t0 + t1) / 2).cgColor)
        context.move(to: p0)
        context.addLine(to: p1)
        context.strokePath()
    }
}

func drawFace(in context: CGContext) {
    let ink = NSColor(calibratedRed: 0.055, green: 0.085, blue: 0.14, alpha: 1)

    context.setFillColor(ink.cgColor)
    context.fillEllipse(in: CGRect(x: 438, y: 360, width: 148, height: 148))

    context.setStrokeColor(ink.cgColor)
    context.setLineWidth(92)
    context.setLineCap(.round)
    context.setLineJoin(.round)

    let left = CGPoint(x: 375, y: 585)
    let right = CGPoint(x: 649, y: 585)
    let control = CGPoint(x: 512, y: 735)

    context.move(to: left)
    context.addQuadCurve(to: right, control: control)
    context.strokePath()
}

func gradientColor(t: CGFloat) -> NSColor {
    let stops: [(CGFloat, NSColor)] = [
        (0.00, NSColor(calibratedRed: 0.38, green: 0.78, blue: 1.00, alpha: 1)),
        (0.18, NSColor(calibratedRed: 0.39, green: 0.88, blue: 0.65, alpha: 1)),
        (0.34, NSColor(calibratedRed: 0.96, green: 0.86, blue: 0.24, alpha: 1)),
        (0.50, NSColor(calibratedRed: 1.00, green: 0.65, blue: 0.30, alpha: 1)),
        (0.66, NSColor(calibratedRed: 0.96, green: 0.36, blue: 0.68, alpha: 1)),
        (0.82, NSColor(calibratedRed: 0.48, green: 0.42, blue: 1.00, alpha: 1)),
        (1.00, NSColor(calibratedRed: 0.28, green: 0.65, blue: 1.00, alpha: 1))
    ]

    guard let lowerIndex = stops.lastIndex(where: { $0.0 <= t }) else {
        return stops[0].1
    }

    let upperIndex = min(lowerIndex + 1, stops.count - 1)
    let lower = stops[lowerIndex]
    let upper = stops[upperIndex]

    if lowerIndex == upperIndex {
        return lower.1
    }

    let localT = (t - lower.0) / (upper.0 - lower.0)
    return mix(lower.1, upper.1, t: localT)
}

func mix(_ a: NSColor, _ b: NSColor, t: CGFloat) -> NSColor {
    let left = a.usingColorSpace(.deviceRGB) ?? a
    let right = b.usingColorSpace(.deviceRGB) ?? b

    return NSColor(
        calibratedRed: left.redComponent + (right.redComponent - left.redComponent) * t,
        green: left.greenComponent + (right.greenComponent - left.greenComponent) * t,
        blue: left.blueComponent + (right.blueComponent - left.blueComponent) * t,
        alpha: left.alphaComponent + (right.alphaComponent - left.alphaComponent) * t
    )
}

func writePNG(_ image: CGImage, to url: URL) throws {
    let bitmap = NSBitmapImageRep(cgImage: image)
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Unable to encode PNG")
    }

    try png.write(to: url)
}
