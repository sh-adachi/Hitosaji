import AppKit

// Original spoon-and-leaf mark, drawn with native vector paths.
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()
NSColor(srgbRed: 0.21, green: 0.39, blue: 0.31, alpha: 1).setFill()
NSRect(origin: .zero, size: size).fill()
NSColor(srgbRed: 0.95, green: 0.95, blue: 0.88, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 467, y: 174, width: 90, height: 421), xRadius: 45, yRadius: 45).fill()
NSBezierPath(ovalIn: NSRect(x: 350, y: 455, width: 324, height: 374)).fill()
NSColor(srgbRed: 0.66, green: 0.77, blue: 0.57, alpha: 1).setFill()
let leaf = NSBezierPath()
leaf.move(to: NSPoint(x: 531, y: 550))
leaf.curve(to: NSPoint(x: 805, y: 705), controlPoint1: NSPoint(x: 546, y: 725), controlPoint2: NSPoint(x: 701, y: 750))
leaf.curve(to: NSPoint(x: 531, y: 550), controlPoint1: NSPoint(x: 778, y: 567), controlPoint2: NSPoint(x: 656, y: 522))
leaf.fill()
NSColor(srgbRed: 0.21, green: 0.39, blue: 0.31, alpha: 1).setStroke()
let vein = NSBezierPath()
vein.move(to: NSPoint(x: 550, y: 566))
vein.curve(to: NSPoint(x: 736, y: 668), controlPoint1: NSPoint(x: 602, y: 602), controlPoint2: NSPoint(x: 664, y: 640))
vein.lineWidth = 12
vein.lineCapStyle = .round
vein.stroke()
image.unlockFocus()
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
