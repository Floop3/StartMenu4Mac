import CoreGraphics
import Foundation
import ImageIO

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("APP ICON CHECK FAILED: \(message)\n".utf8))
    exit(1)
}

let directory = URL(fileURLWithPath: CommandLine.arguments.last ?? "")
let filenames = ["16.png", "32.png", "64.png", "128.png", "256.png", "512.png", "1024.png"]
let colorSpace = CGColorSpaceCreateDeviceRGB()
let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue).union(.byteOrder32Big)

for filename in filenames {
    let url = directory.appendingPathComponent(filename)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        fail("cannot decode \(url.path)")
    }

    let width = image.width
    let height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    pixels.withUnsafeMutableBytes { storage in
        guard let context = CGContext(
            data: storage.baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            fail("could not decode pixels for \(filename)")
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }

    var minX = width
    var minY = height
    var maxX = -1
    var maxY = -1
    var colorMinX = width
    var colorMinY = height
    var colorMaxX = -1
    var colorMaxY = -1

    for y in 0..<height {
        for x in 0..<width {
            let offset = (y * width + x) * 4
            let red = Int(pixels[offset])
            let green = Int(pixels[offset + 1])
            let blue = Int(pixels[offset + 2])
            let alpha = pixels[offset + 3]
            guard alpha > 16 else { continue }

            minX = min(minX, x)
            minY = min(minY, y)
            maxX = max(maxX, x)
            maxY = max(maxY, y)

            if alpha > 127 && max(red, green, blue) - min(red, green, blue) > 80 {
                colorMinX = min(colorMinX, x)
                colorMinY = min(colorMinY, y)
                colorMaxX = max(colorMaxX, x)
                colorMaxY = max(colorMaxY, y)
            }
        }
    }

    guard maxX >= minX, colorMaxX >= colorMinX else { fail("missing artwork in \(filename)") }

    let insets = [
        Double(minX) / Double(width),
        Double(minY) / Double(height),
        Double(width - 1 - maxX) / Double(width),
        Double(height - 1 - maxY) / Double(height)
    ]
    let tolerance = width <= 32 ? 0.05 : 0.025
    guard insets.allSatisfy({ abs($0 - 0.09) <= tolerance }) else {
        fail("\(filename) outer insets are \(insets.map { String(format: "%.3f", $0) }.joined(separator: ",")); expected about 0.09")
    }

    let markWidth = Double(colorMaxX - colorMinX + 1) / Double(width)
    let markHeight = Double(colorMaxY - colorMinY + 1) / Double(height)
    let markRasterizationTolerance = max(0.025, 2.0 / Double(width))
    let expectedMarkRange = (0.49 - markRasterizationTolerance)...(0.60 + markRasterizationTolerance)
    guard expectedMarkRange.contains(markWidth), expectedMarkRange.contains(markHeight) else {
        fail("\(filename) four-color mark bounds are \(String(format: "%.3f", markWidth))x\(String(format: "%.3f", markHeight)); expected the entire icon artwork to be scaled to 82%")
    }
}

print("app icon geometry: ok (about 9% transparent outer inset; whole artwork uniformly scaled to 82%)")
