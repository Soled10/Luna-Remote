import AppKit
let folder = "LunaRemote/Assets.xcassets/AppIcon.appiconset"
try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)

// Keep the checked-in Luna Remote brand asset when available. The fallback
// drawing below keeps local builds self-contained if the asset is absent.
let brandedIcon = URL(fileURLWithPath: folder + "/AppIcon.png")
if FileManager.default.fileExists(atPath: brandedIcon.path) {
    let catalog: [String: Any] = ["images": [["filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"]], "info": ["author": "xcode", "version": 1]]
    try JSONSerialization.data(withJSONObject: catalog, options: .prettyPrinted).write(to: URL(fileURLWithPath: folder + "/Contents.json"))
    exit(0)
}

let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor(red: 0.04, green: 0.07, blue: 0.16, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1024, height: 1024)).fill()
NSColor(red: 0.35, green: 0.65, blue: 1, alpha: 1).setStroke()
let monitor = NSBezierPath(roundedRect: NSRect(x: 165, y: 315, width: 694, height: 474), xRadius: 55, yRadius: 55)
monitor.lineWidth = 35
monitor.stroke()
let stand = NSBezierPath()
stand.move(to: NSPoint(x: 512, y: 315))
stand.line(to: NSPoint(x: 512, y: 215))
stand.move(to: NSPoint(x: 360, y: 215))
stand.line(to: NSPoint(x: 664, y: 215))
stand.lineWidth = 35
stand.stroke()
NSColor.white.setFill()
let pointer = NSBezierPath()
pointer.move(to: NSPoint(x: 420, y: 680))
pointer.line(to: NSPoint(x: 420, y: 435))
pointer.line(to: NSPoint(x: 485, y: 492))
pointer.line(to: NSPoint(x: 545, y: 385))
pointer.line(to: NSPoint(x: 601, y: 418))
pointer.line(to: NSPoint(x: 539, y: 520))
pointer.line(to: NSPoint(x: 625, y: 526))
pointer.close()
pointer.fill()
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: folder + "/AppIcon.png"))
let catalog: [String: Any] = ["images": [["filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"]], "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: catalog, options: .prettyPrinted).write(to: URL(fileURLWithPath: folder + "/Contents.json"))
