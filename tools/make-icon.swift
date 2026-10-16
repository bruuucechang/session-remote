// 產生 app 圖示（1024×1024）：swift tools/make-icon.swift ios/Resources/Assets.xcassets/AppIcon.appiconset/icon.png
import AppKit
let size = 1024.0
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
NSColor(calibratedRed: 0.11, green: 0.10, blue: 0.13, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: size, height: size).fill()
// 四格小窗：代表多個 session
let colors: [NSColor] = [.systemOrange, .systemBlue, .systemGreen, .systemGray]
for (i, c) in colors.enumerated() {
    let x = 170.0 + Double(i % 2) * 360, y = 170.0 + Double(1 - i / 2) * 360
    let r = NSBezierPath(roundedRect: NSRect(x: x, y: y, width: 324, height: 324), xRadius: 56, yRadius: 56)
    c.withAlphaComponent(i == 0 ? 1 : 0.85).setFill(); r.fill()
}
let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 150, weight: .bold), .foregroundColor: NSColor.white]
NSString(string: ">_").draw(at: NSPoint(x: 215, y: 610), withAttributes: attrs)
img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
