//
//  Lenslok decoding components
//

import SwiftUI

nonisolated struct LenslokRecognizer {
    typealias Guide = LenslokImage.Guide
    typealias CenterGuide = LenslokImage.CenterGuide
    typealias Marks = LenslokImage.Marks
    typealias Sampling = LenslokImage.Sampling
    typealias PixelImage = LenslokImage.PixelImage

    let title: LenslokDecoder.LenslokTitle

    func guideSlope(in image: PixelImage) -> Double? {
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

    func photographedGuides(in image: PixelImage) -> (Guide, CenterGuide)? {
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
    func singleGuideSlope(in image: PixelImage) -> Double? {
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
    func singleGuide(in image: PixelImage) -> (Guide, CenterGuide, Marks)? {
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
    func verticalGuides(in image: PixelImage) -> (Guide, CenterGuide)? {
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

    func horizontalGuide(in image: PixelImage) -> Guide? {
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

    func centerGuide(in image: PixelImage, guide: Guide) -> CenterGuide? {
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

    func characterMarks(in image: PixelImage, guide: Guide, center: CenterGuide, photographed: Bool = false, verticalOnly: Bool = false) -> Marks? {
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

}
