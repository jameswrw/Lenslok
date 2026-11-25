//
//  Lenslok decoding components
//

import SwiftUI

nonisolated struct LenslokDecoder {
    typealias Guide = LenslokImage.Guide
    typealias CenterGuide = LenslokImage.CenterGuide
    typealias Marks = LenslokImage.Marks
    typealias Sampling = LenslokImage.Sampling
    typealias PixelImage = LenslokImage.PixelImage

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

    private var recognizer: LenslokRecognizer { LenslokRecognizer(title: title) }
    private var sampler: LenslokSampler { LenslokSampler(title: title) }
    private var drawing: LenslokDrawing { LenslokDrawing() }
    
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
        return drawing.withBitmap(of: source) { context, buffer in
            let initialPixels = Array(buffer)
            let background = Array(initialPixels[0..<channels])
            let initialImage = PixelImage(
                pixels: initialPixels, background: background,
                width: width, height: height, channels: channels
            )
            // Tomahawk uses only a center line; other titles require their extra guides.
            if title == .tomahawk || title == .ttRacer,
               recognizer.horizontalGuide(in: initialImage) == nil,
               let (guide, center, marks) = recognizer.singleGuide(in: initialImage),
               let sampling = sampler.samplingPositions(in: initialImage, marks: marks, center: center) {
                drawing.reconstruct(in: buffer, original: initialImage, marks: marks, sampling: sampling)
                if showsGuideOverlay {
                    drawing.drawGuides(in: buffer, width: width, height: height, guide: guide, center: center, showsHorizontal: false)
                }
                return context.makeImage() ?? source
            }
            if title == .tomahawk || title == .ttRacer, let slope = recognizer.singleGuideSlope(in: initialImage) {
                drawing.straighten(source, in: context, background: background, slope: slope)
                let straightened = PixelImage(pixels: Array(buffer), background: background,
                                              width: width, height: height, channels: channels)
                if let (guide, center, marks) = recognizer.singleGuide(in: straightened),
                   let sampling = sampler.samplingPositions(in: straightened, marks: marks, center: center) {
                    drawing.reconstruct(in: buffer, original: straightened, marks: marks, sampling: sampling)
                    if showsGuideOverlay {
                        drawing.drawGuides(in: buffer, width: width, height: height, guide: guide, center: center, showsHorizontal: false)
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
                if let (guide, center) = recognizer.photographedGuides(in: brightImage) {
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
                    if let marks = recognizer.characterMarks(in: screen, guide: guide, center: center, photographed: true),
                       let sampling = sampler.samplingPositions(in: screen, marks: marks, center: center) {
                        drawing.reconstruct(in: buffer, original: screen, marks: marks, sampling: sampling, binarize: true)
                    }
                    if showsGuideOverlay {
                        drawing.drawGuides(in: buffer, width: width, height: height, guide: guide, center: center)
                    }
                    return context.makeImage() ?? source
                }
            }

            // Inverse screens may omit the horizontal bar altogether.
            let backgroundLuminance = (77 * Int(background[0]) + 150 * Int(background[1]) + 29 * Int(background[2])) / 256
            if backgroundLuminance > 128 {
                let darkImage = PixelImage(pixels: initialPixels, background: background,
                                           width: width, height: height, channels: channels, darkGuides: true)
                if let (guide, center) = recognizer.verticalGuides(in: darkImage),
                   let marks = recognizer.characterMarks(in: darkImage, guide: guide, center: center, verticalOnly: true),
                   let sampling = sampler.samplingPositions(in: darkImage, marks: marks, center: center, guideWidth: guide.right - guide.left) {
                    drawing.reconstruct(in: buffer, original: darkImage, marks: marks, sampling: sampling)
                    if showsGuideOverlay {
                        drawing.drawGuides(in: buffer, width: width, height: height, guide: guide, center: center, showsHorizontal: false)
                    }
                    return context.makeImage() ?? source
                }
            }

            // A guide must contain at least this many foreground pixels.
            guard initialImage.foregroundCount > width / 4 else { return source }

            // Aligned guides are common; avoid the much more expensive angle
            // search when both guides can already be located.
            let original: PixelImage
            if let guide = recognizer.horizontalGuide(in: initialImage),
               recognizer.centerGuide(in: initialImage, guide: guide) != nil {
                original = initialImage
            } else if let slope = recognizer.guideSlope(in: initialImage) {
                drawing.straighten(source, in: context, background: background, slope: slope)
                original = PixelImage(
                    pixels: Array(buffer), background: background,
                    width: width, height: height, channels: channels
                )
            } else {
                if showsGuideOverlay, let guide = recognizer.horizontalGuide(in: initialImage) {
                    drawing.drawGuides(in: buffer, width: width, height: height, guide: guide, center: nil)
                    return context.makeImage() ?? source
                }
                return source
            }
            guard let guide = recognizer.horizontalGuide(in: original) else { return source }
            let center = recognizer.centerGuide(in: original, guide: guide)
            if let center,
               let marks = recognizer.characterMarks(in: original, guide: guide, center: center),
               let sampling = sampler.samplingPositions(in: original, marks: marks, center: center) {
                drawing.reconstruct(in: buffer, original: original, marks: marks, sampling: sampling)
            } else if !showsGuideOverlay {
                return source
            }

            if showsGuideOverlay {
                drawing.drawGuides(in: buffer, width: width, height: height, guide: guide, center: center)
            }
            return context.makeImage() ?? source
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
        return drawing.withBitmap(of: cropped, fallback: source) { context, buffer in
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
            var detected = recognizer.photographedGuides(in: bright)
            if detected == nil && darkGuides {
                detected = recognizer.verticalGuides(in: bright)
                verticalOnly = detected != nil
            }
            if detected == nil, title == .tomahawk || title == .ttRacer, let (guide, center, marks) = recognizer.singleGuide(in: bright) {
                detected = (guide, center)
                singleMarks = marks
                verticalOnly = true
            }
            var appliedSlope = 0.0
            if detected == nil, let estimate = ((title == .tomahawk || title == .ttRacer) ? recognizer.singleGuideSlope(in: bright) : recognizer.guideSlope(in: bright)) {
                // Thin camera lines can bias the coarse angle estimate. Check a
                // few nearby angles and keep only a complete crosshair shape.
                for adjustment in [0.0, 0.01, -0.01, 0.02, -0.02, 0.03, -0.03, 0.04, -0.04] {
                    let slope = estimate + adjustment
                    drawing.straighten(cropped, in: context, background: background, slope: slope)
                    original = Array(buffer)
                    bright = PixelImage(pixels: original, background: background,
                                        width: width, height: height, channels: channels,
                                        brightGuides: !darkGuides, darkGuides: darkGuides)
                    detected = recognizer.photographedGuides(in: bright)
                    if detected == nil && darkGuides {
                        detected = recognizer.verticalGuides(in: bright)
                        verticalOnly = detected != nil
                    }
                    if detected == nil, title == .tomahawk || title == .ttRacer, let (guide, center, marks) = recognizer.singleGuide(in: bright) {
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
            guard let marks = singleMarks ?? recognizer.characterMarks(in: bright, guide: guide, center: center, photographed: true, verticalOnly: verticalOnly),
                  let sampling = sampler.samplingPositions(in: bright, marks: marks, center: center,
                                                   guideWidth: verticalOnly && singleMarks == nil ? guide.right - guide.left : nil)
            else { return source }
            drawing.reconstruct(in: buffer, original: bright, marks: marks, sampling: sampling,
                        binarize: true, blackBackground: !darkGuides, inverted: darkGuides)
            if showsGuideOverlay {
                drawing.drawGuides(in: buffer, width: width, height: height, guide: guide, center: center,
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

}
