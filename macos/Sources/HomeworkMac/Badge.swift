import AppKit
import CoreGraphics
import Foundation

/// 班徽素材：去掉自带透明边距后缓存，保证「按框居中」等于视觉居中
enum Badge {
    private static var cached: NSImage?
    private static var missing = false

    static var image: NSImage? {
        if let cached { return cached }
        if missing { return nil }
        guard let url = locate(), let data = try? Data(contentsOf: url), let src = NSImage(data: data) else {
            missing = true
            return nil
        }
        let cropped = cropToInk(src) ?? src
        cached = cropped
        return cropped
    }

    private static func locate() -> URL? {
        if let url = Bundle.main.url(forResource: "badge", withExtension: "png") { return url }
        if let url = Bundle.module.url(forResource: "badge", withExtension: "png") { return url }
        return nil
    }

    /// 扫描 alpha 通道量出墨迹范围并裁掉四周透明边
    private static func cropToInk(_ image: NSImage) -> NSImage? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let cg = rep.cgImage,
              let data = rep.bitmapData else { return nil }
        let w = rep.pixelsWide
        let h = rep.pixelsHigh
        guard w > 0, h > 0, rep.samplesPerPixel >= 4 else { return nil }
        let rowBytes = rep.bytesPerRow
        let spp = rep.samplesPerPixel

        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            let row = data + y * rowBytes
            for x in 0..<w where row[x * spp + 3] > 8 {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        let rect = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        guard let cropped = cg.cropping(to: rect) else { return nil }
        return NSImage(cgImage: cropped, size: NSSize(width: rect.width, height: rect.height))
    }
}
