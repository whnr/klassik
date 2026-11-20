import CoreGraphics
import SwiftUI
import Testing
import UIKit

@testable import Klassik

@MainActor
struct FavouriteTitleTests {
    @Test func aLongAlbumTitleDrawsItsFavouriteMark() throws {
        let title = "A very long album title with several complete works for orchestra and chamber ensemble"
        for size in [DynamicTypeSize.large, .accessibility3] {
            let renderer = ImageRenderer(
                content: AlbumCoverTitle(title: title, isFavourite: true)
                    .environment(\.dynamicTypeSize, size)
                    .environment(\.colorScheme, .light)
                    .frame(width: 140)
                    .background(.white))
            // A bitmap context avoids simulator GPU preparation during the first text attachment draw.
            var rendered: UIImage?
            renderer.render { size, draw in
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1
                rendered = UIGraphicsImageRenderer(size: size, format: format).image { draw($0.cgContext) }
            }
            let image = try #require(rendered?.cgImage)
            #expect(CGFloat(image.height) > TypeStyle.subheadline.size * 3, "The title needs more than two lines")
            var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
            let context = try #require(
                CGContext(
                    data: &pixels, width: image.width, height: image.height,
                    bitsPerComponent: 8, bytesPerRow: image.width * 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            // Only the favourite mark uses red ink; accessibility values cannot prove that it is visible.
            let redPixels = stride(from: 0, to: pixels.count, by: 4).filter {
                Int(pixels[$0]) > Int(pixels[$0 + 1]) + 60 && Int(pixels[$0]) > Int(pixels[$0 + 2]) + 30
            }
            #expect(redPixels.count > 10, "The long title hides its favourite mark at \(size)")
        }
    }

    @Test func theMarkTakesTapsInAHitTargetAroundItself() {
        let mark = CGRect(x: 200, y: 20, width: 22, height: 14)
        let area = FermataShape.hitArea(around: mark)
        #expect(area.width == Measure.hitTarget)
        #expect(area.height == Measure.hitTarget)
        #expect(area.midX == mark.midX)
        #expect(area.midY == mark.midY)
        #expect(!area.contains(CGPoint(x: 20, y: 27)))
        #expect(!area.contains(CGPoint(x: mark.minX - Measure.hitTarget, y: mark.midY)))
    }

    @Test func aLargeMarkKeepsItsOwnFrame() {
        let mark = CGRect(x: 0, y: 0, width: Measure.hitTarget * 2, height: Measure.hitTarget * 2)
        #expect(FermataShape.hitArea(around: mark) == mark)
    }

    @Test func noMarkTakesNoTap() {
        #expect(FermataShape.hitArea(around: .null).isNull)
        #expect(!FermataShape.hitArea(around: .null).contains(CGPoint.zero))
    }
}
