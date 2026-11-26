//
//  Lenslok decoding components
//

import SwiftUI

nonisolated enum LenslokImage {
    struct Guide {
        let y: Int
        let left: Int
        let right: Int
    }

    struct CenterGuide {
        let x: Int
        let right: Int
        let start: Int
        let end: Int
    }

    struct Marks {
        let top: Int
        let bottom: Int
        let left: Int
        let right: Int
    }

    struct Sampling {
        let columns: [Int?]
    }

    struct PixelImage {
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
                    // Bright guides can acquire a color cast from the camera or display.
                    let luminance = (77 * Int(pixels[pixel]) + 150 * Int(pixels[pixel + 1]) + 29 * Int(pixels[pixel + 2])) / 256
                    isForeground = luminance > 180
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

}
