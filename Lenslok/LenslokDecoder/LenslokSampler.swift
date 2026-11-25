//
//  Lenslok decoding components
//

import SwiftUI

nonisolated struct LenslokSampler {
    typealias Guide = LenslokImage.Guide
    typealias CenterGuide = LenslokImage.CenterGuide
    typealias Marks = LenslokImage.Marks
    typealias Sampling = LenslokImage.Sampling
    typealias PixelImage = LenslokImage.PixelImage

    let title: LenslokDecoder.LenslokTitle

    func samplingPositions(in image: PixelImage, marks: Marks, center: CenterGuide, guideWidth: Int? = nil) -> Sampling? {
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

}
