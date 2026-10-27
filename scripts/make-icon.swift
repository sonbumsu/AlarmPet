// make-icon.swift
// Writes the AlarmPet app icon (the alarm-clock cat from AlarmCatArt) as iconset PNGs.
//
//   swiftc -O scripts/make-icon.swift AlarmPet/Utilities/AlarmCatArt.swift -o /tmp/make-icon
//   /tmp/make-icon AlarmPet/Resources/AppIcon.iconset

import AppKit

@main
enum MakeIcon {
    static func main() throws {
        let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset")
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        for points in [16, 32, 128, 256, 512] {
            try render(pixels: points).write(to: outDir.appendingPathComponent("icon_\(points)x\(points).png"))
            try render(pixels: points * 2).write(to: outDir.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
        }
        print("✅ \(outDir.path)")
    }

    static func render(pixels: Int) -> Data {
        let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .high
        ctx.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        AlarmCatArt.draw(in: ctx)
        return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
    }
}
