import AppKit
import CoreText
let sizes = [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)]
try FileManager.default.createDirectory(atPath: "work/icon.iconset", withIntermediateDirectories: true)
for (base, scale) in sizes {
 let n = base * scale
 let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n*4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
 ctx.scaleBy(x: CGFloat(n)/1024, y: CGFloat(n)/1024)
 ctx.setFillColor(CGColor(gray: 8.0/255, alpha: 1))
 ctx.addPath(CGPath(roundedRect: CGRect(x:32,y:32,width:960,height:960), cornerWidth:220, cornerHeight:220, transform:nil)); ctx.fillPath()
 ctx.setStrokeColor(CGColor(gray:1,alpha:1)); ctx.setLineWidth(26)
 ctx.addPath(CGPath(roundedRect: CGRect(x:32,y:32,width:960,height:960), cornerWidth:220, cornerHeight:220, transform:nil)); ctx.strokePath()
 ctx.addPath(CGPath(roundedRect: CGRect(x:116,y:116,width:792,height:792), cornerWidth:142, cornerHeight:142, transform:nil)); ctx.strokePath()
 let text = NSAttributedString(string: "MM", attributes: [.font: NSFont(name:"HelveticaNeue-Bold",size:250)!, .foregroundColor:NSColor.white, .kern: -14])
 let line = CTLineCreateWithAttributedString(text)
 let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
 ctx.textPosition = CGPoint(x:512-bounds.midX,y:512-bounds.midY)
 CTLineDraw(line,ctx)
 let data = NSBitmapImageRep(cgImage:ctx.makeImage()!).representation(using:.png,properties:[:])!
 let suffix = scale == 2 ? "@2x" : ""
 try data.write(to:URL(fileURLWithPath:"work/icon.iconset/icon_\(base)x\(base)\(suffix).png"))
 if n == 1024 { try data.write(to:URL(fileURLWithPath:"outputs/CLR MIDI Monitor Icon.png")) }
}
