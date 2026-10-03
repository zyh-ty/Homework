#!/usr/bin/env swift
// 生成 macOS 风格应用图标（圆角方形 + 渐变 + 班徽）→ AppIcon.icns
// 用法：swift scripts/make-icon.swift <badge.png> <输出目录>

import AppKit
import CoreGraphics
import Foundation

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("用法: make-icon.swift <badge.png> <outDir>")
    exit(1)
}
let badgeURL = URL(fileURLWithPath: args[1])
let outDir = URL(fileURLWithPath: args[2])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

guard let badgeImage = NSImage(contentsOf: badgeURL),
      let tiff = badgeImage.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let rawBadge = rep.cgImage else {
    print("无法读取班徽素材")
    exit(1)
}

/// 裁掉班徽四周透明边，保证视觉居中
func cropToInk(_ image: CGImage) -> CGImage {
    guard let data = image.dataProvider?.data,
          let ptr = CFDataGetBytePtr(data) else { return image }
    let w = image.width
    let h = image.height
    let bpr = image.bytesPerRow
    let bpp = image.bitsPerPixel / 8
    guard bpp >= 4 else { return image }
    var minX = w, minY = h, maxX = -1, maxY = -1
    for y in 0..<h {
        for x in 0..<w where ptr[y * bpr + x * bpp + 3] > 8 {
            if x < minX { minX = x }
            if x > maxX { maxX = x }
            if y < minY { minY = y }
            if y > maxY { maxY = y }
        }
    }
    guard maxX >= minX, maxY >= minY else { return image }
    return image.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)) ?? image
}

let badge = cropToInk(rawBadge)

func makeIcon(size: CGFloat) -> CGImage? {
    let px = Int(size)
    guard let ctx = CGContext(
        data: nil,
        width: px,
        height: px,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    let inset = size * 0.086
    let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = rect.width * 0.2237
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // 底部阴影
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.018), blur: size * 0.045,
                  color: CGColor(red: 0.05, green: 0.10, blue: 0.22, alpha: 0.35))
    ctx.addPath(path)
    ctx.setFillColor(CGColor(red: 0.16, green: 0.32, blue: 0.58, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    // 渐变主体
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let colors = [
        CGColor(red: 0.44, green: 0.66, blue: 0.92, alpha: 1),
        CGColor(red: 0.20, green: 0.42, blue: 0.76, alpha: 1),
        CGColor(red: 0.11, green: 0.26, blue: 0.51, alpha: 1),
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.55, 1]) {
        ctx.drawLinearGradient(gradient,
                               start: CGPoint(x: rect.minX, y: rect.maxY),
                               end: CGPoint(x: rect.maxX, y: rect.minY),
                               options: [])
    }
    // 顶部高光
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.16))
    ctx.fillEllipse(in: CGRect(x: rect.minX - rect.width * 0.2, y: rect.maxY - rect.height * 0.42,
                               width: rect.width * 1.4, height: rect.height * 0.7))
    ctx.restoreGState()

    // 班徽
    ctx.saveGState()
    let badgeSize = rect.width * 0.62
    let badgeRect = CGRect(x: rect.midX - badgeSize / 2, y: rect.midY - badgeSize / 2 - size * 0.012,
                           width: badgeSize, height: badgeSize)
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.012), blur: size * 0.03,
                  color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.35))
    ctx.draw(badge, in: badgeRect)
    ctx.restoreGState()

    // 内描边
    ctx.addPath(path)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.22))
    ctx.setLineWidth(max(1, size * 0.006))
    ctx.strokePath()

    return ctx.makeImage()
}

let iconset = outDir.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let variants: [(String, CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for (name, size) in variants {
    guard let image = makeIcon(size: size) else { continue }
    let url = iconset.appendingPathComponent("\(name).png")
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { continue }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

// 供 SwiftUI 直接使用的 1024 主图
if let master = makeIcon(size: 1024) {
    let url = outDir.appendingPathComponent("AppIcon-1024.png")
    if let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) {
        CGImageDestinationAddImage(dest, master, nil)
        CGImageDestinationFinalize(dest)
    }
}

let icns = outDir.appendingPathComponent("AppIcon.icns")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "已生成 \(icns.path)" : "iconutil 失败")
