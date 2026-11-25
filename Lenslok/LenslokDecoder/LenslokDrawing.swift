//
//  Lenslok decoding components
//

import SwiftUI

nonisolated struct LenslokDrawing {
    typealias Guide = LenslokImage.Guide
    typealias CenterGuide = LenslokImage.CenterGuide
    typealias Marks = LenslokImage.Marks
    typealias Sampling = LenslokImage.Sampling
    typealias PixelImage = LenslokImage.PixelImage

    func withBitmap(
        of source: CGImage, fallback: CGImage? = nil,
        _ operation: (CGContext, UnsafeMutableRawBufferPointer) -> CGImage
    ) -> CGImage {
        let channels = 4
        let width = source.width
        let height = source.height
        var pixels = [UInt8](repeating: 0, count: width * height * channels)
        return pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * channels,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return fallback ?? source }
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
            return operation(context, buffer)
        }
    }

    // Draw only detected lines, including a horizontal-only partial detection.
    // Working in bitmap coordinates keeps the overlay aligned after straightening.
    func drawGuides(
        in buffer: UnsafeMutableRawBufferPointer, width: Int, height: Int,
        guide: Guide, center: CenterGuide?, showsHorizontal: Bool = true
    ) {
        let thickness = max(1, width / 500)
        let dashLength = max(4, width / 80)
        func paint(_ x: Int, _ y: Int, red: UInt8, green: UInt8, blue: UInt8) {
            guard x >= 0, x < width, y >= 0, y < height else { return }
            let index = (y * width + x) * 4
            buffer[index] = red
            buffer[index + 1] = green
            buffer[index + 2] = blue
            buffer[index + 3] = 255
        }
        if showsHorizontal {
            for x in guide.left..<guide.right where (x - guide.left) / dashLength % 2 == 0 {
                for offset in 0..<thickness {
                    paint(x, guide.y + offset, red: 0, green: 255, blue: 0)
                }
            }
        }
        if let center {
            for y in center.start..<center.end where (y - center.start) / dashLength % 2 == 0 {
                for offset in 0..<thickness {
                    paint(center.x + offset, y, red: 255, green: 80, blue: 0)
                }
            }
        }
    }

    func straighten(_ source: CGImage, in context: CGContext, background: [UInt8], slope: Double) {
        let width = source.width
        let height = source.height
        // The background fills the corners exposed by straightening.
        context.setFillColor(red: CGFloat(background[0]) / 255,
                             green: CGFloat(background[1]) / 255,
                             blue: CGFloat(background[2]) / 255,
                             alpha: CGFloat(background[3]) / 255)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.saveGState()
        context.translateBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
        context.rotate(by: atan(slope))
        context.interpolationQuality = .none
        context.draw(source, in: CGRect(x: -CGFloat(width) / 2, y: -CGFloat(height) / 2,
                                        width: CGFloat(width), height: CGFloat(height)))
        context.restoreGState()
    }

    func reconstruct(
        in buffer: UnsafeMutableRawBufferPointer, original image: PixelImage,
        marks: Marks, sampling: Sampling, binarize: Bool = false, blackBackground: Bool = false,
        inverted: Bool = false
    ) {
        let width = image.width
        let channels = image.channels
        let original = image.pixels
        let background = image.background
        let top = marks.top
        let bottom = marks.bottom
        let left = marks.left
        let right = marks.right
        let columns = sampling.columns
        for y in top...bottom {
            for x in left..<right {
                let slot = ((x - left + 1) * columns.count - 1) / (right - left)
                let destination = (y * width + x) * channels
                if let sampleX = columns[slot] {
                    // Sample the center of each encoded slice, as the lens does,
                    // and expand it to one column of the reconstructed characters.
                    let sourcePixel = (y * width + sampleX) * channels
                    if binarize {
                        let foreground = image.isForeground(sampleX, y)
                        for channel in 0..<3 {
                            buffer[destination + channel] = inverted
                                ? (foreground ? 0 : background[channel])
                                : (foreground ? 255 : 0)
                        }
                        buffer[destination + 3] = 255
                    } else {
                        for channel in 0..<channels {
                            buffer[destination + channel] = original[sourcePixel + channel]
                        }
                    }
                } else if binarize && blackBackground {
                    for channel in 0..<3 { buffer[destination + channel] = 0 }
                    buffer[destination + 3] = 255
                } else {
                    for channel in 0..<channels {
                        buffer[destination + channel] = background[channel]
                    }
                }
            }
        }

    }
}
