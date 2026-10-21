import AppKit

// 차곡 앱 아이콘 (1024px PNG). 파란 바탕에 차곡차곡 쌓인 막대 세 개.
let size: CGFloat = 1024
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

let inset: CGFloat = 100
let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let path = CGPath(roundedRect: rect, cornerWidth: 185, cornerHeight: 185, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.22).cgColor)
ctx.addPath(path)
ctx.setFillColor(NSColor(srgbRed: 0.145, green: 0.388, blue: 0.922, alpha: 1).cgColor)
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(path)
ctx.clip()
let colors = [NSColor(srgbRed: 0.231, green: 0.510, blue: 0.965, alpha: 1).cgColor,
              NSColor(srgbRed: 0.114, green: 0.306, blue: 0.847, alpha: 1).cgColor] as CFArray
let grad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: size - inset), end: CGPoint(x: 0, y: inset), options: [])

// 막대 세 개 (아래가 가장 넓고 진함)
let barH: CGFloat = 92
let gap: CGFloat = 44
let widths: [CGFloat] = [520, 400, 280]
let alphas: [CGFloat] = [1.0, 0.82, 0.58]
let baseY: CGFloat = size / 2 - (barH * 3 + gap * 2) / 2 - 10
for i in 0..<3 {
    let w = widths[i]
    let r = CGRect(x: (size - w) / 2, y: baseY + CGFloat(i) * (barH + gap), width: w, height: barH)
    ctx.addPath(CGPath(roundedRect: r, cornerWidth: barH / 2, cornerHeight: barH / 2, transform: nil))
    ctx.setFillColor(NSColor.white.withAlphaComponent(alphas[i]).cgColor)
    ctx.fillPath()
}
// 작은 보라 점 (기록 하나가 더 쌓이는 느낌)
let dot = CGRect(x: size / 2 + 140 + 30, y: baseY + 2 * (barH + gap) + 4, width: 84, height: 84)
ctx.setFillColor(NSColor(srgbRed: 0.486, green: 0.227, blue: 0.929, alpha: 1).cgColor)
ctx.fillEllipse(in: dot)
ctx.restoreGState()

img.unlockFocus()

guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
do { try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1])) } catch { exit(1) }
