import AppKit
import XCTest
@testable import JoyCoding

final class EliteControllerArtworkTests: XCTestCase {
    private func source() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(
            "Assets/ControllerArt/XboxEliteSeries2Controller.svg"), encoding: .utf8)
    }

    func testEveryFrontInputHasASharedSurfaceIncludingStickDirections() throws {
        let frontInputs = DeviceArt.xboxElite2.anchors.filter { $0.kind != .paddle }
        XCTAssertEqual(Set(frontInputs.map(\.id)), Set(EliteControllerArtwork.regions.keys))
        let masks = try XCTUnwrap(EliteControllerArtwork.highlightSources(source: source()))
        XCTAssertEqual(masks.count, 15)
        XCTAssertNotEqual(masks["lt"], masks["lb"])
        XCTAssertNotEqual(masks["rt"], masks["rb"])
        XCTAssertEqual(EliteControllerArtwork.regions[9],
                       EliteControllerArtwork.regions[StickChannel.left.anchorID])
        XCTAssertEqual(EliteControllerArtwork.regions[10],
                       EliteControllerArtwork.regions[StickChannel.right.anchorID])
    }

    func testNativeMasksCoverTheirControlsWithoutPaintingTheControllerBody() throws {
        let artwork = try XCTUnwrap(EliteControllerArtwork(source: source()))
        for anchor in DeviceArt.xboxElite2.anchors where anchor.kind != .paddle {
            let region = try XCTUnwrap(EliteControllerArtwork.regions[anchor.id])
            let image = try XCTUnwrap(artwork.highlight(region: region))
            let bitmap = try XCTUnwrap(NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 829, pixelsHigh: 610,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            image.draw(in: NSRect(x: 0, y: 0, width: 829, height: 610))
            NSGraphicsContext.restoreGraphicsState()
            let x = Int(anchor.pos.x * 829), y = Int(anchor.pos.y * 610)
            XCTAssertGreaterThan(bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0,
                                 0.1, "\(region) must cover its actual button center")
            XCTAssertEqual(bitmap.colorAt(x: 410, y: 470)?.alphaComponent, 0,
                           "\(region) must not paint the lower shell")
            XCTAssertEqual(bitmap.colorAt(x: 10, y: 10)?.alphaComponent, 0,
                           "\(region) must retain a transparent full viewBox")
        }
    }
}
