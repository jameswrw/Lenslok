//
//  LenslokVisionRecognizer.swift
//  Lenslok
//

import CoreGraphics
import Vision

// Vision supplies the contours; the same scheme-specific geometry checks used
// by the standard recognizer distinguish guides from unrelated screen edges.
nonisolated struct LenslokVisionRecognizer {
    typealias PixelImage = LenslokImage.PixelImage
    typealias Guide = LenslokImage.Guide
    typealias CenterGuide = LenslokImage.CenterGuide
    typealias Marks = LenslokImage.Marks

    struct Detection {
        let guide: Guide
        let center: CenterGuide
        let marks: Marks
        let verticalOnly: Bool
        let guideWidth: Int?
    }

    let title: LenslokDecoder.LenslokTitle

    func recognize(_ image: PixelImage, darkOnLight: Bool, photographed: Bool) -> Detection? {
        guard let mask = contourMask(image) else { return nil }
        let geometry = LenslokRecognizer(title: title)

        if darkOnLight, let (guide, center) = geometry.verticalGuides(in: mask),
           let marks = geometry.characterMarks(in: mask, guide: guide, center: center, photographed: photographed, verticalOnly: true) {
            return Detection(guide: guide, center: center, marks: marks, verticalOnly: true, guideWidth: guide.right - guide.left)
        }

        if title == .tomahawk {
            guard let (guide, center, marks) = geometry.singleGuide(in: mask, photographed: photographed) else { return nil }
            return Detection(guide: guide, center: center, marks: marks, verticalOnly: true, guideWidth: nil)
        }

        if let (guide, center) = geometry.photographedGuides(in: mask),
           let marks = geometry.characterMarks(in: mask, guide: guide, center: center, photographed: photographed) {
            return Detection(guide: guide, center: center, marks: marks, verticalOnly: false, guideWidth: nil)
        }

        if title == .ttRacer,
           let (guide, center, marks) = geometry.singleGuide(in: mask) {
            return Detection(guide: guide, center: center, marks: marks, verticalOnly: true, guideWidth: nil)
        }

        if let guide = geometry.horizontalGuide(in: mask),
           let center = geometry.centerGuide(in: mask, guide: guide),
           let marks = geometry.characterMarks(in: mask, guide: guide, center: center, photographed: photographed) {
            return Detection(guide: guide, center: center, marks: marks, verticalOnly: false, guideWidth: nil)
        }
        return nil
    }

    private func contourMask(_ image: PixelImage) -> PixelImage? {
        let width = image.width
        let height = image.height
        let channels = 4
        var binary = [UInt8](repeating: 0, count: width * height * channels)
        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * channels
                let value: UInt8 = image.isForeground(x, y) ? 255 : 0
                binary[index] = value
                binary[index + 1] = value
                binary[index + 2] = value
                binary[index + 3] = 255
            }
        }
        guard let binaryImage = binary.withUnsafeMutableBytes({ buffer -> CGImage? in
            CGContext(data: buffer.baseAddress, width: width, height: height,
                      bitsPerComponent: 8, bytesPerRow: width * channels,
                      space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }) else { return nil }
        let request = VNDetectContoursRequest()
        request.detectsDarkOnLight = false
        request.maximumImageDimension = 1024
        do {
            try VNImageRequestHandler(cgImage: binaryImage, options: [:]).perform([request])
        } catch {
            return nil
        }
        guard let observation = request.results?.first else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * channels)
        return pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * channels,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            context.setFillColor(gray: 1, alpha: 1)
            context.scaleBy(x: CGFloat(width), y: CGFloat(height))
            context.addPath(observation.normalizedPath)
            context.drawPath(using: .eoFill)
            return PixelImage(pixels: Array(buffer), background: [0, 0, 0, 0],
                              width: width, height: height, channels: channels)
        }
    }
}
