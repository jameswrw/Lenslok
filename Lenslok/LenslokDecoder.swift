//
//  LenslokDecoder.swift
//  Lenslok
//
//  Created by James Weatherley on 22/11/2026.
//

import SwiftUI

nonisolated struct LenslokDecoder {
    struct HorizontalGuides {
        let guideLeft: Int
        let guideRight: Int
    }

    private struct Guide {
        let y: Int
        let left: Int
        let right: Int
    }

    private struct CenterGuide {
        let x: Int
        let right: Int
        let start: Int
        let end: Int
    }

    private struct Marks {
        let top: Int
        let bottom: Int
        let left: Int
        let right: Int
    }

    private struct Sampling {
        let sortedOffsets: [Int]
        let samples: [Int]
    }

    private struct PixelImage {
        let pixels: [UInt8]
        let background: [UInt8]
        let width: Int
        let height: Int
        let channels: Int

        func isForeground(_ x: Int, _ y: Int) -> Bool {
            let index = (y * width + x) * channels
            return (0..<3).contains {
                abs(Int(pixels[index + $0]) - Int(background[$0])) > 40
            }
        }
    }

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
        return Image(decorative: unscramble(image: source), scale: 1).interpolation(.none)
    }

    func unscramble(image source: CGImage) -> CGImage {
        let width = source.width
        let height = source.height
        let channels = 4
        var pixels = [UInt8](repeating: 0, count: width * height * channels)

        return pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * channels,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return source }

            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
            let initialPixels = Array(buffer)
            let background = Array(initialPixels[0..<channels])
            let initialImage = PixelImage(
                pixels: initialPixels, background: background,
                width: width, height: height, channels: channels
            )
            if let slope = guideSlope(in: initialImage) {
                straighten(source, in: context, background: background, slope: slope)
            }

            let original = PixelImage(
                pixels: Array(buffer), background: background,
                width: width, height: height, channels: channels
            )
            guard let guide = horizontalGuide(in: original),
                  let center = centerGuide(in: original, guide: guide),
                  let marks = characterMarks(in: original, guide: guide, center: center),
                  let sampling = samplingPositions(in: original, marks: marks, center: center)
            else { return source }

            reconstruct(in: buffer, original: original, marks: marks, sampling: sampling)
            guard let decoded = context.makeImage() else { return source }
            return decoded
        }
    }

    private func guideSlope(in image: PixelImage) -> Double? {
        let width = image.width
        let height = image.height
        let channels = image.channels
        let initialPixels = image.pixels
        let background = image.background
        // Find the angle with the strongest horizontal projection. Sampling every
        // fourth pixel keeps the search inexpensive while tolerating JPEG edges.
        let maximumSlope = 0.12
        let padding = Int(Double(width) * maximumSlope) + 2
        var foregroundPoints: [(x: Int, y: Int)] = []
        for y in stride(from: 0, to: height, by: 4) {
            for x in stride(from: 0, to: width, by: 4) {
                let pixel = (y * width + x) * channels
                if (0..<3).contains(where: {
                    abs(Int(initialPixels[pixel + $0]) - Int(background[$0])) > 40
                }) {
                    foregroundPoints.append((x, y))
                }
            }
        }
        var bestSlope = 0.0
        var bestCount = 0
        for step in -24...24 {
            let slope = Double(step) * 0.005
            var projection = [Int](repeating: 0, count: height + 2 * padding)
            for point in foregroundPoints {
                let intercept = point.y - Int((slope * Double(point.x)).rounded()) + padding
                projection[intercept / 4] += 1
            }
            let count = projection.max() ?? 0
            if count > bestCount {
                bestCount = count
                bestSlope = slope
            }
        }

        return abs(bestSlope) >= 0.01 && bestCount > width / 16 ? bestSlope : nil
    }

    private func straighten(_ source: CGImage, in context: CGContext, background: [UInt8], slope: Double) {
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

    private func horizontalGuide(in image: PixelImage) -> Guide? {
        let width = image.width
        let height = image.height
        let isForeground = image.isForeground
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
        guard guideRight - guideLeft > width / 4 else { return nil }

        return Guide(y: guideY, left: guideLeft, right: guideRight)
    }

    private func centerGuide(in image: PixelImage, guide: Guide) -> CenterGuide? {
        let height = image.height
        let guideLeft = guide.left
        let guideRight = guide.right
        let guideY = guide.y
        let isForeground = image.isForeground
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
        guard guideWidth > 0, centerEnd - centerStart > height / 4 else { return nil }

        return CenterGuide(x: centerX, right: centerRight, start: centerStart, end: centerEnd)
    }

    private func characterMarks(in image: PixelImage, guide: Guide, center: CenterGuide) -> Marks? {
        let guideWidth = guide.right - guide.left
        let guideLeft = guide.left
        let guideRight = guide.right
        let guideY = guide.y
        let centerX = center.x
        let centerRight = center.right
        let centerStart = center.start
        let centerEnd = center.end
        let isForeground = image.isForeground
        // Inspect both sides: the center guide can be clipped by the image edge,
        // so its shorter side does not necessarily contain the characters.
        // Ignore the outer and center guides when measuring the marks.
        let guideMargin = max(1, guideWidth / 100)
        let scanRows = Array(centerStart..<max(centerStart, guideY - guideMargin))
            + Array(min(centerEnd, guideY + guideMargin + 1)..<centerEnd)
        let margin = max(1, guideWidth / eliteOffsets.count)
        let scanLeft = guideLeft + margin
        let scanRight = guideRight - margin
        let centerExclusion = max(guideWidth / 50, centerRight - centerX)
        let occupiedRows = scanRows.filter { y in
            let foregroundCount = (scanLeft..<scanRight).reduce(into: 0) { count, x in
                if abs(x - centerX) > centerExclusion && isForeground(x, y) {
                    count += 1
                }
            }
            return foregroundCount > 0 && foregroundCount < (scanRight - scanLeft) / 2
        }
        guard let top = occupiedRows.first, let bottom = occupiedRows.last,
              bottom >= top else { return nil }

        let occupiedColumns = (scanLeft..<scanRight).filter { x in
            abs(x - centerX) > centerExclusion
                && occupiedRows.contains { isForeground(x, $0) }
        }
        guard let left = occupiedColumns.first, let last = occupiedColumns.last,
              last > left else { return nil }
        let right = last + 1

        return Marks(top: top, bottom: bottom, left: left, right: right)
    }

    private func samplingPositions(in image: PixelImage, marks: Marks, center: CenterGuide) -> Sampling? {
        let width = image.width
        let left = marks.left
        let right = marks.right
        let centerX = center.x
        // The outermost marks cover full strips; the table samples their centers.
        // Inset each edge by one output strip before fitting the outer offsets.
        let sortedOffsets = eliteOffsets.compactMap { $0 }.sorted()
        guard let minimumOffset = sortedOffsets.first,
              let maximumOffset = sortedOffsets.last,
              maximumOffset > minimumOffset else { return nil }
        let markWidth = Double(right - left)
        let sampleSpan = markWidth * Double(eliteOffsets.count - 2) / Double(eliteOffsets.count)
        let selectionWidth = sampleSpan * 100 / Double(maximumOffset - minimumOffset)
        let samples = sortedOffsets.map {
            centerX + Int((selectionWidth * Double($0) / 100).rounded())
        }
        guard let firstSample = samples.first, let lastSample = samples.last,
              firstSample >= 0, lastSample < width else { return nil }

        return Sampling(sortedOffsets: sortedOffsets, samples: samples)
    }

    private func reconstruct(
        in buffer: UnsafeMutableRawBufferPointer, original image: PixelImage,
        marks: Marks, sampling: Sampling
    ) {
        let width = image.width
        let channels = image.channels
        let original = image.pixels
        let background = image.background
        let top = marks.top
        let bottom = marks.bottom
        let left = marks.left
        let right = marks.right
        let sortedOffsets = sampling.sortedOffsets
        let samples = sampling.samples
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

    }
}
