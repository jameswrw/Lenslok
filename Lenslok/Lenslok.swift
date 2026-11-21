//
//  Lenslok.swift
//  Lenslok
//

import SwiftUI

struct Lenslok {
    // LensKey's Elite sample positions, expressed as percentages of the lens
    // selection width from the center guide. Nil denotes a blank column.
    private let eliteOffsets: [Int?] = [
        nil, -41, -57, -77, 10, -28, -19, nil,
        nil, 43, -10, 22, 32, 77, 58, nil
    ]

    @MainActor
    func unscramble(image: Image) -> Image {
        let renderer = ImageRenderer(content: image)
        renderer.scale = 1
        guard let source = renderer.cgImage else { return image }

        let width = source.width
        let height = source.height
        let channels = 4
        var pixels = [UInt8](repeating: 0, count: width * height * channels)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        return pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * channels,
                space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return image }

            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
            let original = pixelsFromBuffer(buffer)
            let background = Array(original[0..<channels])

            func isForeground(_ x: Int, _ y: Int) -> Bool {
                let index = (y * width + x) * channels
                return (0..<3).contains {
                    abs(Int(original[index + $0]) - Int(background[$0])) > 40
                }
            }

            // Locate the longest uninterrupted horizontal guide.
            var guideY = 0
            var guideLeft = 0
            var guideRight = 0
            for y in 0..<height {
                var start: Int?
                for x in 0...width {
                    if x < width && isForeground(x, y) {
                        if start == nil { start = x }
                    } else if let runStart = start {
                        if x - runStart > guideRight - guideLeft {
                            guideY = y
                            guideLeft = runStart
                            guideRight = x
                        }
                        start = nil
                    }
                }
            }
            guard guideRight - guideLeft > width / 4 else { return image }

            // The center guide is the longest vertical line crossing that guide.
            var centerX = guideLeft
            var centerStart = guideY
            var centerEnd = guideY
            for x in guideLeft..<guideRight where isForeground(x, guideY) {
                var start = guideY
                var end = guideY + 1
                while start > 0 && isForeground(x, start - 1) { start -= 1 }
                while end < height && isForeground(x, end) { end += 1 }
                if end - start > centerEnd - centerStart {
                    centerX = x
                    centerStart = start
                    centerEnd = end
                }
            }
            var centerRight = centerX + 1
            while centerRight < guideRight && isForeground(centerRight, centerStart)
                && isForeground(centerRight, centerEnd - 1) {
                centerRight += 1
            }
            centerX = (centerX + centerRight - 1) / 2
            let guideWidth = guideRight - guideLeft
            guard guideWidth > 0, centerEnd - centerStart > height / 4 else { return image }

            // Find the character rows on the shorter side of the center guide.
            // Ignore the outer and center guides when measuring the marks.
            let scanRows = guideY - centerStart < centerEnd - guideY
                ? Array(centerStart..<guideY)
                : Array((guideY + 1)..<centerEnd)
            let margin = max(1, guideWidth / eliteOffsets.count)
            let scanLeft = guideLeft + margin
            let scanRight = guideRight - margin
            let centerExclusion = max(1, centerRight - centerX)
            let occupiedRows = scanRows.filter { y in
                let foregroundCount = (scanLeft..<scanRight).reduce(into: 0) { count, x in
                    if abs(x - centerX) > centerExclusion && isForeground(x, y) {
                        count += 1
                    }
                }
                return foregroundCount > 0 && foregroundCount < (scanRight - scanLeft) / 2
            }
            guard let top = occupiedRows.first, let bottom = occupiedRows.last,
                  bottom >= top else { return image }

            let occupiedColumns = (scanLeft..<scanRight).filter { x in
                abs(x - centerX) > centerExclusion
                    && occupiedRows.contains { isForeground(x, $0) }
            }
            guard let left = occupiedColumns.first, let last = occupiedColumns.last,
                  last > left else { return image }
            let right = last + 1

            // The outermost marks cover full strips; the table samples their centers.
            // Inset each edge by one output strip before fitting the outer offsets.
            let sortedOffsets = eliteOffsets.compactMap { $0 }.sorted()
            guard let minimumOffset = sortedOffsets.first,
                  let maximumOffset = sortedOffsets.last,
                  maximumOffset > minimumOffset else { return image }
            let markWidth = Double(right - left)
            let sampleSpan = markWidth * Double(eliteOffsets.count - 2) / Double(eliteOffsets.count)
            let selectionWidth = sampleSpan * 100 / Double(maximumOffset - minimumOffset)
            let samples = sortedOffsets.map {
                centerX + Int((selectionWidth * Double($0) / 100).rounded())
            }
            guard let firstSample = samples.first, let lastSample = samples.last,
                  firstSample >= 0, lastSample < width else { return image }

            for y in top...bottom {
                for x in left..<right {
                    let slot = ((x - left + 1) * eliteOffsets.count - 1) / (right - left)
                    let destination = (y * width + x) * channels
                    if let offset = eliteOffsets[slot],
                       let sourceIndex = sortedOffsets.firstIndex(of: offset) {
                        // Sample the center of each encoded slice, as the lens does,
                        // and expand it to one column of the reconstructed characters.
                        let sourcePixel = (y * width + samples[sourceIndex]) * channels
                        for channel in 0..<channels {
                            buffer[destination + channel] = original[sourcePixel + channel]
                        }
                    } else {
                        for channel in 0..<channels {
                            buffer[destination + channel] = background[channel]
                        }
                    }
                }
            }

            guard let decoded = context.makeImage() else { return image }
            return Image(decorative: decoded, scale: 1).interpolation(.none)
        }
    }

    private func pixelsFromBuffer(_ buffer: UnsafeMutableRawBufferPointer) -> [UInt8] {
        Array(buffer)
    }
}
