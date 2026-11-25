//
//  LenslokDecoder.swift
//  Lenslok
//
//  Created by James Weatherley on 22/11/2026.
//

import SwiftUI

nonisolated struct LenslokDecoder {
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
        let columns: [Int?]
    }

    private struct PixelImage {
        let pixels: [UInt8]
        let background: [UInt8]
        let width: Int
        let height: Int
        let channels: Int
        private let foreground: [UInt8]
        let foregroundCount: Int

        init(pixels: [UInt8], background: [UInt8], width: Int, height: Int, channels: Int, brightGuides: Bool = false, darkGuides: Bool = false) {
            self.pixels = pixels
            self.background = background
            self.width = width
            self.height = height
            self.channels = channels
            var mask = [UInt8](repeating: 0, count: width * height)
            var count = 0
            let backgroundLuminance = (77 * Int(background[0]) + 150 * Int(background[1]) + 29 * Int(background[2])) / 256
            for index in 0..<mask.count {
                let pixel = index * channels
                let isForeground: Bool
                if darkGuides {
                    let luminance = (77 * Int(pixels[pixel]) + 150 * Int(pixels[pixel + 1]) + 29 * Int(pixels[pixel + 2])) / 256
                    isForeground = luminance < backgroundLuminance - 40
                } else if brightGuides {
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

    enum LenslokTitle: CaseIterable, Identifiable, Sendable {
        case ace, artStudio, elite, graphicAdventureCreator
        case jewelsOfDarkness, princeOfMagik, tomahawk, ttRacer

        var id: Self { self }

        var displayName: LocalizedStringResource {
            switch self {
            case .ace: "ACE"
            case .artStudio: "Art Studio"
            case .elite: "Elite"
            case .graphicAdventureCreator: "Graphic Adventure Creator"
            case .jewelsOfDarkness: "Jewels of Darkness"
            case .princeOfMagik: "The Price of Magik"
            case .tomahawk: "Tomahawk"
            case .ttRacer: "TT Racer"
            }
        }

        // Percentages of lens selection width from the center; nil is a blank.
        // Table from Simon Owen's lenskey: https://github.com/simonowen/lenskey/
        var offsets: [Int?] {
            switch self {
            case .ace:                     [nil, -81, -31,  13, -62, -41, 22,  nil, nil, -22,  39, 58, -12, 29, 70, nil]
            case .artStudio:               [nil, -41, -30, -68, -52, -11, -20, nil, nil,  32,  60, 11,  22, 49, 71, nil]
            case .elite:                   [nil, -41, -57, -77,  10, -28, -19, nil, nil,  43, -10, 22,  32, 77, 58, nil]
            case .graphicAdventureCreator: [nil, -77, -28,  -4, -19, -59, -39, nil, nil,  20,  51, 10,  10, 66, 28, nil]
            case .jewelsOfDarkness:        [nil, -40, -57, -71,  14, -27, -21, nil, nil,  42, -12, 22,  27, 67, 53, nil]
            case .princeOfMagik:           [nil, -27, -39, -71,  -6, -17, -48, nil, nil,  51,  64,  7,  40, 17, 79, nil]
            case .tomahawk:                [nil, -82, -31, -58, -20, -42,  10, nil, nil, -10,  32, 65,  20, 44, 80, nil]
            case .ttRacer:                 [nil, -20, -41, -69, -53,   6, -29, nil, nil,  -9,  64, 20,  46, 33, 81, nil]
            }
        }
    }
    
    var title: LenslokTitle = .elite
    
    @MainActor
    func unscramble(image: Image, showsGuideOverlay: Bool = false) -> Image {
        let renderer = ImageRenderer(content: image)
        renderer.scale = 1
        guard let source = renderer.cgImage else { return image }
        return Image(decorative: unscramble(image: source, showsGuideOverlay: showsGuideOverlay), scale: 1).interpolation(.none)
    }

    func unscramble(image source: CGImage, showsGuideOverlay: Bool = false, videoMode: Bool = false) -> CGImage {
        if videoMode {
            return unscrambleVideoFrame(source, showsGuideOverlay: showsGuideOverlay)
        }
        let width = source.width
        let height = source.height
        let channels = 4
        return withBitmap(of: source) { context, buffer in
            let initialPixels = Array(buffer)
            let background = Array(initialPixels[0..<channels])
            let initialImage = PixelImage(
                pixels: initialPixels, background: background,
                width: width, height: height, channels: channels
            )
            // Tomahawk uses only a center line; other titles require their extra guides.
            if title == .tomahawk || title == .ttRacer,
               horizontalGuide(in: initialImage) == nil,
               let (guide, center, marks) = singleGuide(in: initialImage),
               let sampling = samplingPositions(in: initialImage, marks: marks, center: center) {
                reconstruct(in: buffer, original: initialImage, marks: marks, sampling: sampling)
                if showsGuideOverlay {
                    drawGuides(in: buffer, width: width, height: height, guide: guide, center: center, showsHorizontal: false)
                }
                return context.makeImage() ?? source
            }
            if title == .tomahawk || title == .ttRacer, let slope = singleGuideSlope(in: initialImage) {
                straighten(source, in: context, background: background, slope: slope)
                let straightened = PixelImage(pixels: Array(buffer), background: background,
                                              width: width, height: height, channels: channels)
                if let (guide, center, marks) = singleGuide(in: straightened),
                   let sampling = samplingPositions(in: straightened, marks: marks, center: center) {
                    reconstruct(in: buffer, original: straightened, marks: marks, sampling: sampling)
                    if showsGuideOverlay {
                        drawGuides(in: buffer, width: width, height: height, guide: guide, center: center, showsHorizontal: false)
                    }
                    return context.makeImage() ?? source
                }
                context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
            }
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

            // Inverse screens may omit the horizontal bar altogether.
            let backgroundLuminance = (77 * Int(background[0]) + 150 * Int(background[1]) + 29 * Int(background[2])) / 256
            if backgroundLuminance > 128 {
                let darkImage = PixelImage(pixels: initialPixels, background: background,
                                           width: width, height: height, channels: channels, darkGuides: true)
                if let (guide, center) = verticalGuides(in: darkImage),
                   let marks = characterMarks(in: darkImage, guide: guide, center: center, verticalOnly: true),
                   let sampling = samplingPositions(in: darkImage, marks: marks, center: center, guideWidth: guide.right - guide.left) {
                    reconstruct(in: buffer, original: darkImage, marks: marks, sampling: sampling)
                    if showsGuideOverlay {
                        drawGuides(in: buffer, width: width, height: height, guide: guide, center: center, showsHorizontal: false)
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

    private func withBitmap(
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

    // The camera alignment rectangle is expressed in image coordinates.
    static func videoSearchRect(width: Int, height: Int) -> CGRect {
        CGRect(x: width / 100, y: height * 14 / 100,
               width: width * 98 / 100, height: height * 42 / 100)
    }

    private func unscrambleVideoFrame(_ source: CGImage, showsGuideOverlay: Bool) -> CGImage {
        let search = Self.videoSearchRect(width: source.width, height: source.height)
        guard let cropped = source.cropping(to: search) else { return source }
        let width = cropped.width
        let height = cropped.height
        let channels = 4
        return withBitmap(of: cropped, fallback: source) { context, buffer in
            var original = Array(buffer)
            let background = Array(original[0..<channels])
            let backgroundLuminance = (77 * Int(background[0]) + 150 * Int(background[1]) + 29 * Int(background[2])) / 256
            let darkGuides = backgroundLuminance > 128
            var bright = PixelImage(pixels: original, background: background,
                                    width: width, height: height, channels: channels,
                                    brightGuides: !darkGuides, darkGuides: darkGuides)
            let inputBright = bright
            var verticalOnly = false
            var singleMarks: Marks?
            var detected = photographedGuides(in: bright)
            if detected == nil && darkGuides {
                detected = verticalGuides(in: bright)
                verticalOnly = detected != nil
            }
            if detected == nil, title == .tomahawk || title == .ttRacer, let (guide, center, marks) = singleGuide(in: bright) {
                detected = (guide, center)
                singleMarks = marks
                verticalOnly = true
            }
            var appliedSlope = 0.0
            if detected == nil, let estimate = ((title == .tomahawk || title == .ttRacer) ? singleGuideSlope(in: bright) : guideSlope(in: bright)) {
                // Thin camera lines can bias the coarse angle estimate. Check a
                // few nearby angles and keep only a complete crosshair shape.
                for adjustment in [0.0, 0.01, -0.01, 0.02, -0.02, 0.03, -0.03, 0.04, -0.04] {
                    let slope = estimate + adjustment
                    straighten(cropped, in: context, background: background, slope: slope)
                    original = Array(buffer)
                    bright = PixelImage(pixels: original, background: background,
                                        width: width, height: height, channels: channels,
                                        brightGuides: !darkGuides, darkGuides: darkGuides)
                    detected = photographedGuides(in: bright)
                    if detected == nil && darkGuides {
                        detected = verticalGuides(in: bright)
                        verticalOnly = detected != nil
                    }
                    if detected == nil, title == .tomahawk || title == .ttRacer, let (guide, center, marks) = singleGuide(in: bright) {
                        detected = (guide, center)
                        singleMarks = marks
                        verticalOnly = true
                    }
                    if detected != nil {
                        appliedSlope = slope
                        break
                    }
                }
            }
            guard let (guide, center) = detected,
                  guide.left > 2, guide.right < width - 2 else { return source }
            // A bright stroke crossing the search boundary indicates a clipped
            // crosshair. Its apparent endpoint cannot be used for sampling.
            let edgeTop = max(0, guide.y - width / 12)
            let edgeBottom = min(height, guide.y + width / 12)
            guard !(edgeTop..<edgeBottom).contains(where: {
                inputBright.isForeground(0, $0) || inputBright.isForeground(width - 1, $0)
            }) else { return source }
            guard let marks = singleMarks ?? characterMarks(in: bright, guide: guide, center: center, photographed: true, verticalOnly: verticalOnly),
                  let sampling = samplingPositions(in: bright, marks: marks, center: center,
                                                   guideWidth: verticalOnly && singleMarks == nil ? guide.right - guide.left : nil)
            else { return source }
            reconstruct(in: buffer, original: bright, marks: marks, sampling: sampling,
                        binarize: true, blackBackground: !darkGuides, inverted: darkGuides)
            if showsGuideOverlay {
                drawGuides(in: buffer, width: width, height: height, guide: guide, center: center,
                           showsHorizontal: !verticalOnly)
            }
            guard let decoded = context.makeImage(),
                  let full = CGContext(data: nil, width: source.width, height: source.height,
                                       bitsPerComponent: 8, bytesPerRow: source.width * channels,
                                       space: CGColorSpaceCreateDeviceRGB(),
                                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return source }
            full.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
            let destination = CGRect(x: search.minX, y: CGFloat(source.height) - search.maxY,
                                     width: search.width, height: search.height)
            // Rotate the decoded patch back so it stays registered with the camera frame.
            full.saveGState()
            let inset = CGFloat(max(width, height)) * abs(appliedSlope) / 2 + 1
            full.clip(to: destination.insetBy(dx: inset, dy: inset))
            full.translateBy(x: destination.midX, y: destination.midY)
            full.rotate(by: -atan(appliedSlope))
            full.interpolationQuality = .none
            full.draw(decoded, in: CGRect(x: -search.width / 2, y: -search.height / 2,
                                          width: search.width, height: search.height))
            full.restoreGState()
            return full.makeImage() ?? source
        }
    }

    // Draw only detected lines, including a horizontal-only partial detection.
    // Working in bitmap coordinates keeps the overlay aligned after straightening.
    private func drawGuides(
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
                let barOffset = max(3, span / 10)
                func hasBar(near x: Int) -> Bool {
                    let radius = max(2, width / 150)
                    for sampleX in max(0, x - radius)...min(width - 1, x + radius) {
                        for dy in -radius...radius {
                            let above = y - barOffset + dy
                            let below = y + barOffset + dy
                            if above >= 0 && image.isForeground(sampleX, above) { return true }
                            if below < height && image.isForeground(sampleX, below) { return true }
                        }
                    }
                    return false
                }
                guard y >= barOffset, y + barOffset < height,
                      hasBar(near: left), hasBar(near: right) else { continue }
                bestWidth = span
                best = (Guide(y: y, left: left, right: right + 1), center)
            }
        }
        return best
    }

    // Estimate a vertical line's lean when it is too rotated to form a long
    // uninterrupted run in a single column.
    private func singleGuideSlope(in image: PixelImage) -> Double? {
        let width = image.width
        let height = image.height
        func lineCenter(at y: Int) -> Int? {
            var best: Int?
            var start: Int?
            for x in (width / 4)...(width * 3 / 4) {
                if image.isForeground(x, y) {
                    if start == nil { start = x }
                } else if let first = start {
                    let center = (first + x - 1) / 2
                    if x - first < max(4, width / 40),
                       best.map({ abs(center - width / 2) < abs($0 - width / 2) }) ?? true {
                        best = center
                    }
                    start = nil
                }
            }
            return best
        }
        let top = height / 4
        let bottom = height * 3 / 4
        guard let topX = lineCenter(at: top), let bottomX = lineCenter(at: bottom) else { return nil }
        let slope = -Double(bottomX - topX) / Double(bottom - top)
        return abs(slope) >= 0.01 && abs(slope) <= 0.12 ? slope : nil
    }

    // Tomahawk has no outer guides. Require a long, narrow central line with
    // character marks on both sides and clear space at both ends.
    private func singleGuide(in image: PixelImage) -> (Guide, CenterGuide, Marks)? {
        let width = image.width
        let height = image.height
        let step = max(1, width / 800)
        let gap = max(2, width / 500)
        var candidates: [CenterGuide] = []

        for x in stride(from: width / 4, to: width * 3 / 4, by: step) {
            var start: Int?
            var last = 0
            for y in stride(from: 0, through: height + gap, by: step) {
                if y < height && image.isForeground(x, y) {
                    if start == nil { start = y }
                    last = y
                } else if let first = start, y - last > gap {
                    if last - first > height / 3 {
                        candidates.append(CenterGuide(x: x, right: x + step, start: first, end: last + 1))
                    }
                    start = nil
                }
            }
        }

        candidates.sort { ($0.end - $0.start) > ($1.end - $1.start) }
        for rawCandidate in candidates.prefix(64) {
            let length = rawCandidate.end - rawCandidate.start
            // A slanted line can appear as a shorter vertical run. Reject it
            // so that the rotation estimator can straighten the whole guide.
            let searchRadius = max(3, width / 80)
            let scanLeft = max(0, rawCandidate.x - searchRadius)
            let scanRight = min(width - 1, rawCandidate.x + searchRadius)
            let before = rawCandidate.start - gap - 1
            let after = rawCandidate.end + gap
            if before >= 0 && (scanLeft...scanRight).contains(where: { image.isForeground($0, before) }) { continue }
            if after < height && (scanLeft...scanRight).contains(where: { image.isForeground($0, after) }) { continue }
            let sampleY = rawCandidate.start + length / 10
            var lineLeft = rawCandidate.x
            var lineRight = rawCandidate.x
            while lineLeft > 0 && image.isForeground(lineLeft - 1, sampleY) { lineLeft -= 1 }
            while lineRight + 1 < width && image.isForeground(lineRight + 1, sampleY) { lineRight += 1 }
            guard lineRight - lineLeft < max(4, width / 40) else { continue }
            let candidate = CenterGuide(x: (lineLeft + lineRight) / 2, right: lineRight + 1,
                                        start: rawCandidate.start, end: rawCandidate.end)
            let middle = (candidate.start + candidate.end) / 2
            let probe = max(3, width / 100)
            guard candidate.x >= probe, candidate.x + probe < width,
                  !image.isForeground(candidate.x - probe, candidate.start + length / 10),
                  !image.isForeground(candidate.x + probe, candidate.start + length / 10),
                  !image.isForeground(candidate.x - probe, candidate.end - length / 10 - 1),
                  !image.isForeground(candidate.x + probe, candidate.end - length / 10 - 1) else { continue }

            let radius = min(width / 2, length * 5 / 4)
            let left = max(0, candidate.x - radius)
            let right = min(width, candidate.x + radius)
            let exclusion = max(probe, width / 100)
            let rows = (candidate.start..<candidate.end).filter { y in
                var count = 0
                for x in left..<right where abs(x - candidate.x) > exclusion {
                    if image.isForeground(x, y) { count += 1 }
                }
                return count > max(1, width / 150)
            }
            guard let top = rows.first, let bottom = rows.last,
                  bottom - top >= 4, bottom - top < length / 2,
                  top > candidate.start + length / 10,
                  bottom < candidate.end - length / 10,
                  abs((top + bottom) / 2 - middle) < length / 3 else { continue }

            let columns = (left..<right).filter { x in
                abs(x - candidate.x) > exclusion
                    && rows.contains { image.isForeground(x, $0) }
            }
            guard let first = columns.first, let last = columns.last,
                  first < candidate.x - exclusion, last > candidate.x + exclusion else { continue }

            let marks = Marks(top: top, bottom: bottom, left: first, right: last + 1)
            let guide = Guide(y: middle, left: first, right: last + 1)
            return (guide, candidate, marks)
        }
        return nil
    }

    // Some titles draw only three vertical bars. Match their relative positions
    // and lengths, then place the inferred baseline above the character marks.
    private func verticalGuides(in image: PixelImage) -> (Guide, CenterGuide)? {
        struct Stroke {
            var left: Int
            var right: Int
            var start: Int
            var end: Int
            var x: Int { (left + right) / 2 }
            var length: Int { end - start }
        }

        let width = image.width
        let height = image.height
        let step = max(1, width / 1000)
        let maxGap = max(2, width / 500)
        let minLength = max(height / 7, width / 20)
        var strokes: [Stroke] = []

        for x in stride(from: 0, to: width, by: step) {
            var start: Int?
            var last = 0
            for y in stride(from: 0, through: height + maxGap, by: step) {
                if y < height && image.isForeground(x, y) {
                    if start == nil { start = y }
                    last = y
                } else if let first = start, y - last > maxGap {
                    if last - first >= minLength {
                        if let index = strokes.indices.last,
                           x - strokes[index].right <= max(2, width / 200),
                           abs(strokes[index].start - first) < maxGap * 2,
                           abs(strokes[index].end - last) < maxGap * 2 {
                            strokes[index].right = x
                        } else {
                            strokes.append(Stroke(left: x, right: x, start: first, end: last + 1))
                        }
                    }
                    start = nil
                }
            }
        }

        // Broad filled regions and character strokes are not guide bars.
        strokes = strokes.filter { $0.right - $0.left < max(4, width / 50) }
        strokes.sort { $0.length > $1.length }
        strokes = Array(strokes.prefix(32))
        var best: (Guide, CenterGuide)?
        var bestSpan = 0
        for center in strokes {
            for left in strokes where left.x < center.x {
                for right in strokes where right.x > center.x {
                    let span = right.x - left.x
                    let outerLength = (left.length + right.length) / 2
                    guard span > width / 4, span > bestSpan,
                          abs(center.x * 2 - left.x - right.x) < span / 8,
                          abs(left.length - right.length) < outerLength / 3,
                          abs((left.start + left.end) - (right.start + right.end)) < outerLength / 2,
                          center.length > outerLength * 3 / 2,
                          center.start < min(left.start, right.start),
                          center.end > max(left.end, right.end) else { continue }
                    let top = (left.start + right.start) / 2
                    let baseline = top + outerLength / 3
                    guard baseline >= center.start, baseline < center.end else { continue }
                    bestSpan = span
                    best = (Guide(y: baseline, left: left.x, right: right.x + 1),
                            CenterGuide(x: center.x, right: center.right + 1,
                                        start: center.start, end: center.end))
                }
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

    private func characterMarks(in image: PixelImage, guide: Guide, center: CenterGuide, photographed: Bool = false, verticalOnly: Bool = false) -> Marks? {
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
        let margin = max(1, guideWidth / (verticalOnly ? 64 : title.offsets.count))
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

    private func samplingPositions(in image: PixelImage, marks: Marks, center: CenterGuide, guideWidth: Int? = nil) -> Sampling? {
        let width = image.width
        let left = marks.left
        let right = marks.right
        let centerX = center.x
        // The outermost marks cover full strips; the table samples their centers.
        // Inset each edge by one output strip before fitting the outer offsets.
        let offsets = title.offsets
        let sortedOffsets = offsets.compactMap { $0 }.sorted()
        guard let minimumOffset = sortedOffsets.first,
              let maximumOffset = sortedOffsets.last,
              maximumOffset > minimumOffset else { return nil }
        let markWidth = Double(right - left)
        let sampleSpan = markWidth * Double(offsets.count - 2) / Double(offsets.count)
        // Vertical-only guides provide a stable width even when the outer character strips are blank.
        let selectionWidth = guideWidth.map { Double($0) / 2 }
            ?? sampleSpan * 100 / Double(maximumOffset - minimumOffset)
        let samples = sortedOffsets.map {
            centerX + Int((selectionWidth * Double($0) / 100).rounded())
        }
        guard let firstSample = samples.first, let lastSample = samples.last,
              firstSample >= 0, lastSample < width else { return nil }

        let columns = offsets.map { offset in
            offset.flatMap { value in sortedOffsets.firstIndex(of: value).map { samples[$0] } }
        }
        return Sampling(columns: columns)
    }

    private func reconstruct(
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
