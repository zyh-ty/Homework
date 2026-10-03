#!/usr/bin/env swift
// 生成 DMG 安装窗口背景图（浅色渐变 + 标题 + 拖拽箭头 + 说明）
// 输出三份：<out>.png（1x）、<out>@2x.png（2x）、<out>.tiff（1x+2x 双分辨率，Finder 用这份才清晰）
// 用法：swift scripts/make-dmg-background.swift <输出.png> [宽] [高]

import AppKit
import CoreGraphics
import Foundation

let args = CommandLine.arguments
guard args.count >= 2 else {
    print("用法: make-dmg-background.swift <out.png> [width] [height]")
    exit(1)
}
let outURL = URL(fileURLWithPath: args[1])
let logicalW = args.count > 2 ? (CGFloat(Double(args[2]) ?? 660)) : 660
let logicalH = args.count > 3 ? (CGFloat(Double(args[3]) ?? 420)) : 420

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: r, green: g, blue: b, alpha: a)
}

/// 按给定缩放渲染整张背景（逻辑坐标固定为 logicalW × logicalH）
func render(scale: CGFloat) -> CGImage? {
    let pxW = Int(logicalW * scale)
    let pxH = Int(logicalH * scale)
    guard let ctx = CGContext(
        data: nil,
        width: pxW,
        height: pxH,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    ctx.scaleBy(x: scale, y: scale)

    // 背景：上下渐变（与应用放映底色同一套色）
    let bgColors = [color(0.973, 0.980, 1.0), color(0.898, 0.933, 0.980)] as CFArray
    if let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: bgColors, locations: [0, 1]) {
        ctx.drawLinearGradient(bg,
                               start: CGPoint(x: 0, y: logicalH),
                               end: CGPoint(x: 0, y: 0),
                               options: [])
    }

    // 顶部柔光：让标题区更亮一点
    ctx.saveGState()
    if let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                             colors: [color(1, 1, 1, 0.75), color(1, 1, 1, 0)] as CFArray,
                             locations: [0, 1]) {
        ctx.drawRadialGradient(glow,
                               startCenter: CGPoint(x: logicalW / 2, y: logicalH),
                               startRadius: 0,
                               endCenter: CGPoint(x: logicalW / 2, y: logicalH),
                               endRadius: logicalW * 0.62,
                               options: [])
    }
    ctx.restoreGState()

    let navy = color(0.106, 0.129, 0.184)
    let gray = color(0.451, 0.486, 0.549)

    let nsctx = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = nsctx

    func draw(_ text: String, size: CGFloat, weight: NSFont.Weight, tint: NSColor,
              topY: CGFloat, tracking: CGFloat = 0) {
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.lineBreakMode = .byWordWrapping
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: tint,
            .paragraphStyle: para,
            .kern: tracking,
        ]
        let attributed = NSAttributedString(string: text, attributes: attrs)
        let height = attributed.boundingRect(with: NSSize(width: logicalW, height: 200),
                                             options: [.usesLineFragmentOrigin]).height
        attributed.draw(in: NSRect(x: 0, y: logicalH - topY - height, width: logicalW, height: height))
    }

    draw("每日作业", size: 27, weight: .semibold, tint: NSColor(cgColor: navy)!,
         topY: 34, tracking: 1.5)
    draw("把左边的 App 拖进 Applications 文件夹即可完成安装", size: 12.5, weight: .regular,
         tint: NSColor(cgColor: gray)!, topY: 74)

    // 拖拽箭头：连接两个图标位置（居中于图标行，见 make-dmg.sh 的图标坐标）
    let arrowY = logicalH - 210
    let x0 = logicalW * 0.415
    let x1 = logicalW * 0.585
    let head: CGFloat = 17

    ctx.saveGState()
    ctx.setLineCap(.round)
    ctx.setStrokeColor(color(0.180, 0.373, 0.639, 0.42))
    ctx.setLineWidth(6)
    ctx.move(to: CGPoint(x: x0, y: arrowY))
    ctx.addLine(to: CGPoint(x: x1 - head * 0.7, y: arrowY))
    ctx.strokePath()

    let headPath = CGMutablePath()
    headPath.move(to: CGPoint(x: x1, y: arrowY))
    headPath.addLine(to: CGPoint(x: x1 - head, y: arrowY + head * 0.62))
    headPath.addLine(to: CGPoint(x: x1 - head, y: arrowY - head * 0.62))
    headPath.closeSubpath()
    ctx.addPath(headPath)
    ctx.setFillColor(color(0.180, 0.373, 0.639, 0.55))
    ctx.fillPath()
    ctx.restoreGState()

    draw("首次打开若提示「无法验证开发者」，请右键点按图标后选「打开」", size: 11,
         weight: .regular, tint: NSColor(cgColor: color(0.541, 0.576, 0.639))!,
         topY: logicalH - 94)

    NSGraphicsContext.restoreGraphicsState()
    return ctx.makeImage()
}

func writePNG(_ image: CGImage, to url: URL) -> Bool {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        return false
    }
    CGImageDestinationAddImage(dest, image, nil)
    return CGImageDestinationFinalize(dest)
}

guard let image1x = render(scale: 1), let image2x = render(scale: 2) else {
    print("渲染失败")
    exit(1)
}

let base = outURL.deletingPathExtension()
let dir = outURL.deletingLastPathComponent()
let pngURL = base.appendingPathExtension("png")
let png2xURL = dir.appendingPathComponent("\(base.lastPathComponent)@2x.png")
let tiffURL = base.appendingPathExtension("tiff")

guard writePNG(image1x, to: pngURL) else {
    print("无法写入 \(pngURL.path)")
    exit(1)
}
_ = writePNG(image2x, to: png2xURL)

// HiDPI TIFF：两个分辨率表示，Finder 在 Retina 上取 2x、普通屏取 1x
let rep1 = NSBitmapImageRep(cgImage: image1x)
rep1.size = NSSize(width: logicalW, height: logicalH)
let rep2 = NSBitmapImageRep(cgImage: image2x)
rep2.size = NSSize(width: logicalW, height: logicalH)
let combined = NSImage(size: NSSize(width: logicalW, height: logicalH))
combined.addRepresentation(rep1)
combined.addRepresentation(rep2)
guard let tiff = combined.tiffRepresentation else {
    print("无法生成 TIFF")
    exit(1)
}
try tiff.write(to: tiffURL)

print("已生成 \(pngURL.lastPathComponent)（\(Int(logicalW))×\(Int(logicalH))）")
print("已生成 \(png2xURL.lastPathComponent)（\(Int(logicalW * 2))×\(Int(logicalH * 2))）")
print("已生成 \(tiffURL.lastPathComponent)（双分辨率）")
