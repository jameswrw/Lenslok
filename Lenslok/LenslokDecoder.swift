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
        private let foreground: [UInt8]
        let foregroundCount: Int

        init(pixels: [UInt8], background: [UInt8], width: Int, height: Int, channels: Int, brightGuides: Bool = false) {
            self.pixels = pixels
            self.background = background
            self.width = width
            self.height = height
            self.channels = channels
            var mask = [UInt8](repeating: 0, count: width * height)
            var count = 0
            for index in 0..<mask.count {
                let pixel = index * channels
                let isForeground: Bool
                if brightGuides {
                    isForeground = pixels[pixel] > 180 && pixels[pixel + 1] > 180 && pixels[pixel + 2] > 180
                } else {
                    isForeground = abs(Int(pixels[pixel]) - Int(background[0])) > 40
                        || abs(Int(pixels[pixel + 1]) - Int(background[1])) > 40
                        || abs(Int(pixels[pixel + 2]) - Int(background[2])) > 40
                }
                if isForeground {
                    mask[index] = 1
                    count += 1
                }
            }
            foreground = mask
            foregroundCount = count
        }

        func isForeground(_ x: Int, _ y: Int) -> Bool {
            foreground[y * width + x] != 0
        }
    }

    // LensKey's Elite sample positions, expressed as percentages of the lens
    // selection width from the center guide. Nil denotes a blank column.
    private let eliteOffsets: [Int?] = [
        nil, -41, -57, -77, 10, -28, -19, nil,
        nil, 43, -10, 22, 32, 77, 58, nil
    ]

    @MainActor
    func unscramble(image: Image, showsGuideOverlay: Bool = false) -> Image {
        let renderer = ImageRenderer(content: image)
        renderer.scale = 1
        guard let source = renderer.cgImage else { return image }
        return Image(decorative: unscramble(image: source, showsGuideOverlay: showsGuideOverlay), scale: 1).interpolation(.none)
    }

    func unscramble(image source: CGImage, showsGuideOverlay: Bool = false) -> CGImage {
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
            // Photographs can have white margins unrelated to the dark screen.
            // Search for the complete bright guide shape before using the corner-based mask.
            if initialImage.foregroundCount > width * height / 3 {
                let brightImage = PixelImage(
                    pixels: initialPixels, background: background,
                    width: width, height: height, channels: channels, brightGuides: true
                )
                if let (guide, center) = photographedGuides(in: brightImage) {
                    // Use a dark nearby screen pixel for blank output strips;
                    // a single arbitrary sample can land on a character or reflection.
                    var darkestIndex = 0
                    var darkestValue = Int.max
                    let span = guide.right - guide.left
                    for y in stride(from: max(0, guide.y - span / 6), to: min(height, guide.y + span / 6), by: max(1, span / 40)) {
                        for x in stride(from: guide.left, to: guide.right, by: max(1, span / 40)) {
                            let index = (y * width + x) * channels
                            let value = Int(initialPixels[index]) + Int(initialPixels[index + 1]) + Int(initialPixels[index + 2])
                            if value < darkestValue { darkestValue = value; darkestIndex = index }
                        }
                    }
                    let localBackground = Array(initialPixels[darkestIndex..<(darkestIndex + channels)])
                    let screen = PixelImage(
                        pixels: initialPixels, background: localBackground,
                        width: width, height: height, channels: channels, brightGuides: true
                    )
                    if let marks = characterMarks(in: screen, guide: guide, center: center, photographed: true),
                       let sampling = samplingPositions(in: screen, marks: marks, center: center) {
                        reconstruct(in: buffer, original: screen, marks: marks, sampling: sampling, binarize: true)
                    }
                    if showsGuideOverlay {
                        drawGuides(in: buffer, width: width, height: height, guide: guide, center: center)
                    }
                    return context.makeImage() ?? source
                }
            }

            // A guide must contain at least this many foreground pixels.
            guard initialImage.foregroundCount > width / 4 else { return source }

            // Aligned guides are common; avoid the much more expensive angle
            // search when both guides can already be located.
            let original: PixelImage
            if let guide = horizontalGuide(in: initialImage),
               centerGuide(in: initialImage, guide: guide) != nil {
                original = initialImage
            } else if let slope = guideSlope(in: initialImage) {
                straighten(source, in: context, background: background, slope: slope)
                original = PixelImage(
                    pixels: Array(buffer), background: background,
                    width: width, height: height, channels: channels
                )
            } else {
                if showsGuideOverlay, let guide = horizontalGuide(in: initialImage) {
                    drawGuides(in: buffer, width: width, height: height, guide: guide, center: nil)
                    return context.makeImage() ?? source
                }
                return source
            }
            guard let guide = horizontalGuide(in: original) else { return source }
            let center = centerGuide(in: original, guide: guide)
            if let center,
               let marks = characterMarks(in: original, guide: guide, center: center),
               let sampling = samplingPositions(in: original, marks: marks, center: center) {
                reconstruct(in: buffer, original: original, marks: marks, sampling: sampling)
            } else if !showsGuideOverlay {
                return source
            }

            if showsGuideOverlay {
                drawGuides(in: buffer, width: width, height: height, guide: guide, center: center)
            }
            return context.makeImage() ?? source
        }
    }

    // Draw only detected lines, including a horizontal-only partial detection.
    // Working in bitmap coordinates keeps the overlay aligned after straightening.
    private func drawGuides(
        in buffer: UnsafeMutableRawBufferPointer, width: Int, height: Int,
        guide: Guide, center: CenterGuide?
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
        for x in guide.left..<guide.right where (x - guide.left) / dashLength % 2 == 0 {
            for offset in 0..<thickness {
                paint(x, guide.y + offset, red: 0, green: 255, blue: 0)
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

    private func guideSlope(in image: PixelImage) -> Double? {
        let width = image.width
        let height = image.height
        // Find the angle with the strongest horizontal projection. Sampling every
        // fourth pixel keeps the search inexpensive while tolerating JPEG edges.
        let maximumSlope = 0.12
        let padding = Int(Double(width) * maximumSlope) + 2
        var foregroundPoints: [(x: Int, y: Int)] = []
        for y in stride(from: 0, to: height, by: 4) {
            for x in stride(from: 0, to: width, by: 4) {
                if image.isForeground(x, y) {
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

    private func photographedGuides(in image: PixelImage) -> (Guide, CenterGuide)? {
        let width = image.width
        let height = image.height
        let step = max(1, width / 600)
        let gap = max(2, width / 250)
        let neighbor = max(8, width / 40)
        var verticals: [CenterGuide] = []

        // A real center guide is a narrow bright stroke, not a solid light margin.
        for x in stride(from: width / 5, to: width * 4 / 5, by: step) {
            var start: Int?
            var last = 0
            for y in stride(from: 0, through: height, by: step) {
                if y < height && image.isForeground(x, y) {
                    if start == nil { start = y }
                    last = y
                } else if let first = start, y - last > gap {
                    let length = last - first
                    if length > width / 5, length < width,
                       x >= neighbor, x + neighbor < width {
                        let middle = (first + last) / 2
                        if !image.isForeground(x - neighbor, middle)
                            && !image.isForeground(x + neighbor, middle) {
                            verticals.append(CenterGuide(x: x, right: x + 1, start: first, end: last + 1))
                        }
                    }
                    start = nil
                }
            }
        }
        verticals.sort { ($0.end - $0.start) > ($1.end - $1.start) }
        var candidates: [CenterGuide] = []
        for vertical in verticals {
            if candidates.allSatisfy({ abs($0.x - vertical.x) > neighbor / 2 }) {
                candidates.append(vertical)
                if candidates.count == 12 { break }
            }
        }

        var best: (Guide, CenterGuide)?
        var bestWidth = 0
        let tolerance = max(2, width / 150)
        for center in candidates {
            let inset = width / 30
            guard center.end - center.start > inset * 2 else { continue }
            for y in stride(from: center.start + inset, to: center.end - inset, by: max(2, step * 2)) {
                func brightNear(_ x: Int) -> Bool {
                    for offset in stride(from: -tolerance, through: tolerance, by: step) {
                        let sampleY = y + offset
                        if sampleY >= 0, sampleY < height, image.isForeground(x, sampleY) { return true }
                    }
                    return false
                }
                guard brightNear(center.x) else { continue }
                var left = center.x
                var right = center.x
                var missing = 0
                for x in stride(from: center.x, through: 0, by: -step) {
                    if brightNear(x) { left = x; missing = 0 }
                    else { missing += step; if missing > gap * 2 { break } }
                }
                missing = 0
                for x in stride(from: center.x, to: width, by: step) {
                    if brightNear(x) { right = x; missing = 0 }
                    else { missing += step; if missing > gap * 2 { break } }
                }
                let span = right - left
                guard span > width / 4, span > bestWidth,
                      abs(2 * center.x - left - right) < span / 3 else { continue }
                // The two short vertical end bars must also cross the horizontal.
                let barOffset = max(3, span / 25)
                guard y >= barOffset, y + barOffset < height,
                      (image.isForeground(left, y - barOffset) || image.isForeground(left, y + barOffset)),
                      (image.isForeground(right, y - barOffset) || image.isForeground(right, y + barOffset))
                else { continue }
                bestWidth = span
                best = (Guide(y: y, left: left, right: right + 1), center)
            }
        }
        return best
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
        guard guideWidth > 0, centerEnd - centerStart > height / 4,
              abs(centerX * 2 - guideLeft - guideRight) < guideWidth / 2 else { return nil }

        return CenterGuide(x: centerX, right: centerRight, start: centerStart, end: centerEnd)
    }

    private func characterMarks(in image: PixelImage, guide: Guide, center: CenterGuide, photographed: Bool = false) -> Marks? {
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
            let minimum = photographed ? guideWidth / 40 : 0
            return foregroundCount > minimum && foregroundCount < (scanRight - scanLeft) / 2
                && (!photographed || abs(y - guideY) < guideWidth / 4)
        }
        guard let top = occupiedRows.first, let bottom = occupiedRows.last,
              bottom >= top else { return nil }

        let occupiedColumns = (scanLeft..<scanRight).filter { x in
            guard abs(x - centerX) > centerExclusion else { return false }
            if photographed {
                let count = occupiedRows.reduce(into: 0) { count, y in
                    if isForeground(x, y) { count += 1 }
                }
                return count > max(2, occupiedRows.count / 12)
            }
            return occupiedRows.contains { isForeground(x, $0) }
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
        marks: Marks, sampling: Sampling, binarize: Bool = false
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
                    if binarize {
                        let color: UInt8 = image.isForeground(samples[sourceIndex], y) ? 255 : 0
                        for channel in 0..<3 { buffer[destination + channel] = color }
                        buffer[destination + 3] = 255
                    } else {
                        for channel in 0..<channels {
                            buffer[destination + channel] = original[sourcePixel + channel]
                        }
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
