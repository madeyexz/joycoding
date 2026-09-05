import AppKit
import Foundation

/// Full-viewBox masks reference the same paths as the visible SVG controls.
/// No independent SwiftUI rectangles, radii, or positions are used to paint
/// front-button highlights, so edits to a surface move its highlight too.
struct EliteControllerArtwork {
    static let regions: [Int: String] = [
        XboxHID.leftTriggerButton: "lt", XboxHID.rightTriggerButton: "rt",
        5: "lb", 6: "rb", 1: "a", 2: "b", 3: "x", 4: "y",
        7: "view", 8: "menu", 9: "left-stick", 10: "right-stick",
        11: "xbox", 12: "profile",
        StickChannel.left.anchorID: "left-stick",
        StickChannel.right.anchorID: "right-stick",
        StickChannel.hat.anchorID: "dpad",
    ]

    let image: NSImage
    private let highlights: [String: NSImage]

    init?(source: String) {
        guard let image = NSImage(data: Data(source.utf8)),
              let masks = Self.highlightSources(source: source) else { return nil }
        let rendered = masks.compactMapValues { NSImage(data: Data($0.utf8)) }
        guard rendered.count == masks.count else { return nil }
        self.image = image
        highlights = rendered
    }

    func highlight(region: String) -> NSImage? {
        highlights[region]
    }

    /// Internal for validation against the shipped asset; output remains SVG.
    static func highlightSources(source: String) -> [String: String]? {
        guard let document = try? XMLDocument(xmlString: source),
              let root = document.rootElement(),
              let viewBox = root.attribute(forName: "viewBox")?.stringValue,
              let definitions = root.elements(forName: "defs").first else { return nil }
        var result: [String: String] = [:]
        for region in Set(regions.values) {
            guard let element = try? root.nodes(forXPath: ".//*[@id='highlight-\(region)']").first
            else { return nil }
            result[region] = """
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="\(viewBox)">
              \(definitions.xmlString)
              <g fill="#ffffff" fill-opacity="0.24" stroke="#ffffff" stroke-width="5"
                 stroke-linejoin="round" stroke-linecap="round">
                \(element.xmlString)
              </g>
            </svg>
            """
        }
        return result
    }
}
