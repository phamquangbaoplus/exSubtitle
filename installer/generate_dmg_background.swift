import Cocoa

let width: CGFloat = 680
let height: CGFloat = 480
let scale: CGFloat = 2.0

let pixelWidth = Int(width * scale)
let pixelHeight = Int(height * scale)

let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let context = CGContext(
    data: nil,
    width: pixelWidth,
    height: pixelHeight,
    bitsPerComponent: 8,
    bytesPerRow: pixelWidth * 4,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fatalError("Failed to create CGContext")
}

let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
NSGraphicsContext.current = graphicsContext

context.scaleBy(x: scale, y: scale)

// 1. Background Gradient (Clean, modern macOS Light theme)
let backgroundColors = [
    NSColor(red: 0.97, green: 0.98, blue: 0.99, alpha: 1.0).cgColor,
    NSColor(red: 0.89, green: 0.91, blue: 0.95, alpha: 1.0).cgColor
] as CFArray

if let gradient = CGGradient(colorsSpace: colorSpace, colors: backgroundColors, locations: [0.0, 1.0]) {
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: height),
        end: CGPoint(x: 0, y: 0),
        options: []
    )
}

// 2. Subtle top ambient light accent
if let ambientGradient = CGGradient(
    colorsSpace: colorSpace,
    colors: [
        NSColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 0.09).cgColor,
        NSColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 0.0).cgColor
    ] as CFArray,
    locations: [0.0, 1.0]
) {
    context.drawRadialGradient(
        ambientGradient,
        startCenter: CGPoint(x: width / 2, y: height - 10),
        startRadius: 0,
        endCenter: CGPoint(x: width / 2, y: height - 10),
        endRadius: 320,
        options: []
    )
}

// Coordinate system:
// Finder window size: 680 x 480.
// In Finder, top-left is (0, 0). Finder icons are at (175, 215) and (505, 215).
// In Cocoa, bottom-left is (0, 0), so Cocoa Y = height - Finder Y = 480 - 215 = 265.
let iconY: CGFloat = 265
let appCenter = CGPoint(x: 175, y: iconY)
let appFolderCenter = CGPoint(x: 505, y: iconY)

// 3. Compact & sleek light cards behind icons with soft drop shadow
func drawIconPlate(center: CGPoint) {
    let plateSize: CGFloat = 138
    let halfSize = plateSize / 2
    let plateRect = CGRect(x: center.x - halfSize, y: center.y - halfSize, width: plateSize, height: plateSize)
    let path = NSBezierPath(roundedRect: plateRect, xRadius: 26, yRadius: 26)
    
    // Soft card shadow
    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -3),
        blur: 12,
        color: NSColor(red: 0.1, green: 0.15, blue: 0.25, alpha: 0.08).cgColor
    )
    
    // Card fill (translucent pure white)
    NSColor.white.withAlphaComponent(0.85).setFill()
    path.fill()
    context.restoreGState()
    
    // Card border
    NSColor(white: 0.0, alpha: 0.06).setStroke()
    path.lineWidth = 1.0
    path.stroke()
}

drawIconPlate(center: appCenter)
drawIconPlate(center: appFolderCenter)

// 4. Vibrant modern blue arrow pointing from App to Applications
func drawArrow() {
    let startX: CGFloat = 270
    let endX: CGFloat = 410
    let arrowY: CGFloat = iconY
    
    let blueColor = NSColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1.0)
    
    // Arrow line
    let arrowPath = NSBezierPath()
    arrowPath.move(to: NSPoint(x: startX, y: arrowY))
    arrowPath.line(to: NSPoint(x: endX, y: arrowY))
    
    // Arrow head
    let headLength: CGFloat = 16
    let headAngle: CGFloat = 12
    arrowPath.move(to: NSPoint(x: endX - headLength, y: arrowY + headAngle))
    arrowPath.line(to: NSPoint(x: endX, y: arrowY))
    arrowPath.line(to: NSPoint(x: endX - headLength, y: arrowY - headAngle))
    
    arrowPath.lineWidth = 4.0
    arrowPath.lineCapStyle = .round
    arrowPath.lineJoinStyle = .round
    
    // Shadow for depth
    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -2),
        blur: 8,
        color: NSColor(red: 0.0, green: 0.40, blue: 0.90, alpha: 0.35).cgColor
    )
    blueColor.setStroke()
    arrowPath.stroke()
    context.restoreGState()
    
    // Trailing chevrons
    for offset: CGFloat in [24, 48] {
        let chevPath = NSBezierPath()
        let cx = endX - headLength - offset
        chevPath.move(to: NSPoint(x: cx - 6, y: arrowY + 7))
        chevPath.line(to: NSPoint(x: cx, y: arrowY))
        chevPath.line(to: NSPoint(x: cx - 6, y: arrowY - 7))
        chevPath.lineWidth = 2.5
        chevPath.lineCapStyle = .round
        chevPath.lineJoinStyle = .round
        
        let alpha = 0.55 - (offset / 100.0)
        blueColor.withAlphaComponent(alpha).setStroke()
        chevPath.stroke()
    }
}

drawArrow()

// 5. Header Title & Subtitle (High contrast dark slate on light background)
let centerStyle = NSMutableParagraphStyle()
centerStyle.alignment = .center

let titleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 25, weight: .bold),
    .foregroundColor: NSColor(red: 0.10, green: 0.13, blue: 0.18, alpha: 1.0),
    .paragraphStyle: centerStyle
]

let appTitle = "exSubtitle"
let titleRect = CGRect(x: 20, y: height - 58, width: width - 40, height: 32)
(appTitle as NSString).draw(in: titleRect, withAttributes: titleAttributes)

let subtitleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 14, weight: .medium),
    .foregroundColor: NSColor(red: 0.35, green: 0.42, blue: 0.52, alpha: 1.0),
    .paragraphStyle: centerStyle
]

let subtitle = "Kéo exSubtitle vào thư mục Applications để cài đặt"
let subtitleRect = CGRect(x: 20, y: height - 88, width: width - 40, height: 22)
(subtitle as NSString).draw(in: subtitleRect, withAttributes: subtitleAttributes)

// 6. Action prompt under the arrow
let actionPromptAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
    .foregroundColor: NSColor(red: 0.0, green: 0.45, blue: 0.95, alpha: 0.95),
    .paragraphStyle: centerStyle
]
let actionPrompt = "KÉO & THẢ"
let actionPromptRect = CGRect(x: 270, y: iconY - 32, width: 140, height: 18)
(actionPrompt as NSString).draw(in: actionPromptRect, withAttributes: actionPromptAttributes)

// 7. Render & Export Retina @2x PNG
guard let cgImage = context.makeImage() else {
    fatalError("Failed to create CGImage")
}

let rep = NSBitmapImageRep(cgImage: cgImage)
rep.size = NSSize(width: width, height: height)

guard let pngData = rep.representation(using: .png, properties: [:]) else {
    fatalError("Failed to encode PNG")
}

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "installer/background.png"
let outputURL = URL(fileURLWithPath: outputPath)

do {
    try pngData.write(to: outputURL)
    print("Successfully generated background image at: \(outputPath)")
} catch {
    print("Error saving image: \(error)")
    exit(1)
}
