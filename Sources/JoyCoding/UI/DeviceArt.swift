import SwiftUI

enum AnchorShape { case circle, capsuleH, capsuleV }
enum AnchorKind { case auto, button, stick, home, share, profile, touchpad, system }

/// 摇杆四向的虚拟锚点 id。用负数, 和真实按键编号错开。
enum StickAnchor {
    static let id = StickChannel.hat.anchorID
    static let keys = ["up", "down", "left", "right"]
    static let arrow = ["up": "arrow.up", "down": "arrow.down",
                        "left": "arrow.left", "right": "arrow.right"]
}
enum Side { case left, right }

/// 手柄上一颗按键的位置。坐标是归一化的 (0...1), 相对手柄本体的外框,
/// 这样换手柄型号只要换一张表, 布局代码不用动。
struct ButtonAnchor: Identifiable {
    let id: Int
    let label: String
    let pos: CGPoint
    let size: CGSize
    let shape: AnchorShape
    let side: Side
    var kind: AnchorKind = .auto
}

/// 手柄外观 + 按键锚点。内置 Joy-Con、Switch Pro、PlayStation 和 Xbox。
enum BodyStyle { case joycon, proController, playstation, xbox, xboxElite2 }

struct DeviceArt {
    let anchors: [ButtonAnchor]
    let aspect: CGFloat          // 宽/高
    let railSide: Side?          // SL/SR 那条滑轨在哪边, nil = 没有
    var style: BodyStyle = .joycon
    /// 帽子开关在这只手柄上叫什么。Joy-Con 上是摇杆, Pro/Xbox 上是十字键。
    var hatLabel: String = L("摇杆")


    /// 锚点在父坐标系里的绝对位置, 给连线用
    static func point(_ a: ButtonAnchor, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + a.pos.x * rect.width,
                y: rect.minY + a.pos.y * rect.height)
    }

    /// 左右 Joy-Con 是两个不同的设备, 产品 ID 也不同, 各画各的。
    static func art(vendor: Int, product: Int) -> DeviceArt {
        switch (vendor, product) {
        case (XboxHID.vendorID, XboxHID.elite2ProductID): return xboxElite2
        case (XboxHID.vendorID, _): return xbox
        case (0x057E, 0x2006): return joyconLeft
        case (0x057E, 0x2007): return joyconRight
        case (0x057E, 0x2009): return proController
        // DualSense / DualSense Edge 有静音键, DualShock 4 没有
        case (0x054C, 0x0CE6), (0x054C, 0x0DF2): return playstation(mute: true)
        case (0x054C, _):                        return playstation(mute: false)
        default:               return DeviceArt(anchors: [], aspect: 1, railSide: nil)
        }
    }

    // Joy-Con (R) 竖持。真机布局: ABXY 在上、摇杆在下、Home 最下
    // (摇杆在上那是左 Joy-Con)。加号在顶部靠外侧那一边。
    static let joyconRight = DeviceArt(
        anchors: [
            .init(id: 16, label: "ZR", pos: .init(x: 0.50, y: 0.012),
                  size: .init(width: 0.62, height: 0.022), shape: .capsuleH, side: .right),
            .init(id: 15, label: "R",  pos: .init(x: 0.50, y: 0.045),
                  size: .init(width: 0.72, height: 0.028), shape: .capsuleH, side: .right),
            // 加号在左上 (实机确认, 2026-08)
            .init(id: 10, label: "+",  pos: .init(x: 0.30, y: 0.115),
                  size: .init(width: 0.13, height: 0.038), shape: .circle, side: .left,
                  kind: .system),
            // ABXY 菱形: X 上 / Y 左 / A 右 / B 下
            .init(id: 2,  label: "X",  pos: .init(x: 0.50, y: 0.235),
                  size: .init(width: 0.21, height: 0.062), shape: .circle, side: .right),
            .init(id: 4,  label: "Y",  pos: .init(x: 0.28, y: 0.310),
                  size: .init(width: 0.21, height: 0.062), shape: .circle, side: .left),
            .init(id: 1,  label: "A",  pos: .init(x: 0.72, y: 0.310),
                  size: .init(width: 0.21, height: 0.062), shape: .circle, side: .right),
            .init(id: 3,  label: "B",  pos: .init(x: 0.50, y: 0.385),
                  size: .init(width: 0.21, height: 0.062), shape: .circle, side: .left),
            // 摇杆在 ABXY 下方
            .init(id: 12, label: L("摇杆按下"), pos: .init(x: 0.50, y: 0.560),
                  size: .init(width: 0.48, height: 0.140), shape: .circle, side: .right),
            .init(id: StickAnchor.id, label: L("摇杆方向"), pos: .init(x: 0.50, y: 0.560),
                  size: .init(width: 0.48, height: 0.140), shape: .circle, side: .left),
            .init(id: 13, label: "⌂",  pos: .init(x: 0.50, y: 0.760),
                  size: .init(width: 0.14, height: 0.040), shape: .circle, side: .right),
            .init(id: 5,  label: "SL", pos: .init(x: 0.035, y: 0.300),
                  size: .init(width: 0.05, height: 0.080), shape: .capsuleV, side: .left),
            .init(id: 6,  label: "SR", pos: .init(x: 0.035, y: 0.600),
                  size: .init(width: 0.05, height: 0.080), shape: .capsuleV, side: .left),
        ],
        aspect: 0.355, railSide: .left)

    // Joy-Con (L) 竖持: 滑轨在【右】, 摇杆在上、四个方向键在下 —— 和右手柄相反。
    // 按键编号沿用实测出来的位序 (1=右 2=上 3=下 4=左)。
    static let joyconLeft = DeviceArt(
        anchors: [
            .init(id: 16, label: "ZL", pos: .init(x: 0.50, y: 0.012),
                  size: .init(width: 0.62, height: 0.022), shape: .capsuleH, side: .left),
            .init(id: 15, label: "L",  pos: .init(x: 0.50, y: 0.045),
                  size: .init(width: 0.72, height: 0.028), shape: .capsuleH, side: .left),
            .init(id: 9,  label: "−",  pos: .init(x: 0.70, y: 0.115),
                  size: .init(width: 0.13, height: 0.038), shape: .circle, side: .right,
                  kind: .system),
            .init(id: 11, label: L("摇杆按下"), pos: .init(x: 0.50, y: 0.235),
                  size: .init(width: 0.48, height: 0.140), shape: .circle, side: .right),
            .init(id: StickAnchor.id, label: L("摇杆方向"), pos: .init(x: 0.50, y: 0.235),
                  size: .init(width: 0.48, height: 0.140), shape: .circle, side: .left),
            .init(id: 2,  label: "↑", pos: .init(x: 0.50, y: 0.430),
                  size: .init(width: 0.19, height: 0.056), shape: .circle, side: .right),
            .init(id: 4,  label: "←", pos: .init(x: 0.29, y: 0.500),
                  size: .init(width: 0.19, height: 0.056), shape: .circle, side: .left),
            .init(id: 1,  label: "→", pos: .init(x: 0.71, y: 0.500),
                  size: .init(width: 0.19, height: 0.056), shape: .circle, side: .right),
            .init(id: 3,  label: "↓", pos: .init(x: 0.50, y: 0.570),
                  size: .init(width: 0.19, height: 0.056), shape: .circle, side: .left),
            .init(id: 14, label: "◉", pos: .init(x: 0.50, y: 0.755),
                  size: .init(width: 0.14, height: 0.040), shape: .circle, side: .right),
            .init(id: 5,  label: "SL", pos: .init(x: 0.965, y: 0.300),
                  size: .init(width: 0.05, height: 0.080), shape: .capsuleV, side: .right),
            .init(id: 6,  label: "SR", pos: .init(x: 0.965, y: 0.600),
                  size: .init(width: 0.05, height: 0.080), shape: .capsuleV, side: .right),
        ],
        aspect: 0.355, railSide: .right)

    // Switch Pro 手柄。16 个按键 + 帽子开关(=十字键) + 四个模拟轴。
    // 按键编号是按 Joy-Con 实测位序(1=A 2=X 3=B 4=Y)外推的, 未实测 ——
    // 映射界面按一下会实时点亮, 对不上照着改这张表即可。
    static let proController = DeviceArt(
        anchors: [
            .init(id: 7,  label: "ZL", pos: .init(x: 0.185, y: 0.020),
                  size: .init(width: 0.17, height: 0.035), shape: .capsuleH, side: .left),
            .init(id: 5,  label: "L",  pos: .init(x: 0.205, y: 0.072),
                  size: .init(width: 0.19, height: 0.042), shape: .capsuleH, side: .left),
            .init(id: 8,  label: "ZR", pos: .init(x: 0.815, y: 0.020),
                  size: .init(width: 0.17, height: 0.035), shape: .capsuleH, side: .right),
            .init(id: 6,  label: "R",  pos: .init(x: 0.795, y: 0.072),
                  size: .init(width: 0.19, height: 0.042), shape: .capsuleH, side: .right),

            .init(id: 11, label: L("左摇杆按下"), pos: .init(x: 0.245, y: 0.300),
                  size: .init(width: 0.155, height: 0.225), shape: .circle, side: .left),
            .init(id: StickAnchor.id, label: L("十字键 / 左摇杆"), pos: .init(x: 0.335, y: 0.560),
                  size: .init(width: 0.13, height: 0.19), shape: .circle, side: .left),

            .init(id: 2,  label: "X", pos: .init(x: 0.775, y: 0.235),
                  size: .init(width: 0.072, height: 0.105), shape: .circle, side: .right),
            .init(id: 1,  label: "A", pos: .init(x: 0.858, y: 0.305),
                  size: .init(width: 0.072, height: 0.105), shape: .circle, side: .right),
            .init(id: 3,  label: "B", pos: .init(x: 0.775, y: 0.375),
                  size: .init(width: 0.072, height: 0.105), shape: .circle, side: .right),
            .init(id: 4,  label: "Y", pos: .init(x: 0.692, y: 0.305),
                  size: .init(width: 0.072, height: 0.105), shape: .circle, side: .left),

            .init(id: 12, label: L("右摇杆按下"), pos: .init(x: 0.648, y: 0.560),
                  size: .init(width: 0.155, height: 0.225), shape: .circle, side: .right),
            .init(id: StickChannel.right.anchorID, label: L("右摇杆方向"),
                  pos: .init(x: 0.648, y: 0.560),
                  size: .init(width: 0.155, height: 0.225), shape: .circle, side: .right),

            .init(id: 9,  label: "−", pos: .init(x: 0.398, y: 0.250),
                  size: .init(width: 0.050, height: 0.072), shape: .circle, side: .left,
                  kind: .system),
            .init(id: 10, label: "+", pos: .init(x: 0.602, y: 0.250),
                  size: .init(width: 0.050, height: 0.072), shape: .circle, side: .right,
                  kind: .system),
            .init(id: 14, label: "◉", pos: .init(x: 0.418, y: 0.420),
                  size: .init(width: 0.048, height: 0.070), shape: .circle, side: .left),
            .init(id: 13, label: "⌂", pos: .init(x: 0.582, y: 0.420),
                  size: .init(width: 0.048, height: 0.070), shape: .circle, side: .right),
        ],
        aspect: 1.45, railSide: nil, style: .proController, hatLabel: L("十字键"))

    /// Standard Xbox Wireless layout, using JoyCoding's canonical button IDs.
    static let xbox = DeviceArt(
        anchors: [
            .init(id: XboxHID.leftTriggerButton, label: "LT", pos: .init(x: 0.220, y: 0.055),
                  size: .init(width: 0.16, height: 0.036), shape: .capsuleH, side: .left),
            .init(id: 5, label: "LB", pos: .init(x: 0.235, y: 0.155),
                  size: .init(width: 0.18, height: 0.042), shape: .capsuleH, side: .left),
            .init(id: XboxHID.rightTriggerButton, label: "RT", pos: .init(x: 0.780, y: 0.055),
                  size: .init(width: 0.16, height: 0.036), shape: .capsuleH, side: .right),
            .init(id: 6, label: "RB", pos: .init(x: 0.765, y: 0.155),
                  size: .init(width: 0.18, height: 0.042), shape: .capsuleH, side: .right),

            .init(id: 9, label: L("左摇杆按下"), pos: .init(x: 0.240, y: 0.445),
                  size: .init(width: 0.140, height: 0.212), shape: .circle, side: .left,
                  kind: .stick),
            .init(id: StickChannel.left.anchorID, label: L("左摇杆方向"),
                  pos: .init(x: 0.240, y: 0.445),
                  size: .init(width: 0.140, height: 0.212), shape: .circle, side: .left),
            .init(id: StickChannel.hat.anchorID, label: L("十字键"),
                  pos: .init(x: 0.368, y: 0.664),
                  size: .init(width: 0.150, height: 0.227), shape: .circle, side: .left),

            // Xbox face layout: Y top / X left / B right / A bottom.
            .init(id: 4, label: "Y", pos: .init(x: 0.765, y: 0.335),
                  size: .init(width: 0.064, height: 0.097), shape: .circle, side: .right),
            .init(id: 3, label: "X", pos: .init(x: 0.694, y: 0.437),
                  size: .init(width: 0.064, height: 0.097), shape: .circle, side: .left),
            .init(id: 2, label: "B", pos: .init(x: 0.833, y: 0.428),
                  size: .init(width: 0.064, height: 0.097), shape: .circle, side: .right),
            .init(id: 1, label: "A", pos: .init(x: 0.761, y: 0.531),
                  size: .init(width: 0.064, height: 0.097), shape: .circle, side: .right),

            .init(id: 10, label: L("右摇杆按下"), pos: .init(x: 0.635, y: 0.674),
                  size: .init(width: 0.140, height: 0.212), shape: .circle, side: .right,
                  kind: .stick),
            .init(id: StickChannel.right.anchorID, label: L("右摇杆方向"),
                  pos: .init(x: 0.635, y: 0.674),
                  size: .init(width: 0.140, height: 0.212), shape: .circle, side: .right),

            .init(id: 7, label: "View", pos: .init(x: 0.425, y: 0.436),
                  size: .init(width: 0.044, height: 0.067), shape: .circle, side: .left,
                  kind: .system),
            .init(id: 8, label: "Menu", pos: .init(x: 0.574, y: 0.436),
                  size: .init(width: 0.044, height: 0.067), shape: .circle, side: .right,
                  kind: .system),
            .init(id: 11, label: "Xbox", pos: .init(x: 0.500, y: 0.285),
                  size: .init(width: 0.074, height: 0.112), shape: .circle, side: .right,
                  kind: .home),
            .init(id: 12, label: "Share", pos: .init(x: 0.500, y: 0.499),
                  size: .init(width: 0.050, height: 0.076), shape: .circle, side: .left,
                  kind: .share),
        ],
        aspect: 1.513, railSide: nil, style: .xbox, hatLabel: L("十字键"))

    /// Elite Series 2 BLE uses gapped raw HID usages, normalized before they
    /// reach this canonical layout. The lower center control is Profile, not
    /// the Share button found on the Series X|S controller.
    static let xboxElite2: DeviceArt = {
        var anchors = xbox.anchors.filter { $0.id != 12 }
        anchors.append(.init(id: 12, label: "Profile",
            pos: .init(x: 0.500, y: 0.499),
            size: .init(width: 0.050, height: 0.076), shape: .circle,
            side: .left, kind: .profile))
        return DeviceArt(anchors: anchors, aspect: xbox.aspect, railSide: nil,
                         style: .xboxElite2, hatLabel: xbox.hatLabel)
    }()

    /// PlayStation 手柄 (DualShock 4 / DualSense)。
    ///
    /// 和 Switch Pro 最大的区别是布局: PS 是【对称】的 —— 十字键在左上、
    /// 面键在右上、两只摇杆并排在下方中间; Pro 手柄是非对称的(左摇杆在上、
    /// 十字键在下)。所以这张表不能照抄 Pro 的坐标。
    ///
    /// 按键编号用的是 DualShock 4 的标准 HID 位序 —— 这个业界比较统一,
    /// 但仍然【未实测】。插上手柄后在映射页逐个按, 设备图会实时点亮。
    static func playstation(mute: Bool) -> DeviceArt {
        var a: [ButtonAnchor] = [
            .init(id: 7,  label: "L2", pos: .init(x: 0.180, y: 0.018),
                  size: .init(width: 0.16, height: 0.036), shape: .capsuleH, side: .left),
            .init(id: 5,  label: "L1", pos: .init(x: 0.200, y: 0.072),
                  size: .init(width: 0.18, height: 0.042), shape: .capsuleH, side: .left),
            .init(id: 8,  label: "R2", pos: .init(x: 0.820, y: 0.018),
                  size: .init(width: 0.16, height: 0.036), shape: .capsuleH, side: .right),
            .init(id: 6,  label: "R1", pos: .init(x: 0.800, y: 0.072),
                  size: .init(width: 0.18, height: 0.042), shape: .capsuleH, side: .right),

            // 十字键在左上 (Pro 手柄这里是左摇杆)
            .init(id: StickChannel.hat.anchorID, label: L("十字键"), pos: .init(x: 0.230, y: 0.290),
                  size: .init(width: 0.13, height: 0.19), shape: .circle, side: .left),

            .init(id: 4, label: "△", pos: .init(x: 0.778, y: 0.222),
                  size: .init(width: 0.068, height: 0.100), shape: .circle, side: .right),
            .init(id: 3, label: "○", pos: .init(x: 0.858, y: 0.292),
                  size: .init(width: 0.068, height: 0.100), shape: .circle, side: .right),
            .init(id: 2, label: "✕", pos: .init(x: 0.778, y: 0.362),
                  size: .init(width: 0.068, height: 0.100), shape: .circle, side: .right),
            .init(id: 1, label: "□", pos: .init(x: 0.698, y: 0.292),
                  size: .init(width: 0.068, height: 0.100), shape: .circle, side: .left),

            .init(id: 9,  label: "Create",  pos: .init(x: 0.352, y: 0.150),
                  size: .init(width: 0.038, height: 0.075), shape: .capsuleV, side: .left),
            .init(id: 10, label: "Options", pos: .init(x: 0.648, y: 0.150),
                  size: .init(width: 0.038, height: 0.075), shape: .capsuleV, side: .right),
            .init(id: 14, label: L("触摸板"), pos: .init(x: 0.500, y: 0.245),
                  size: .init(width: 0.235, height: 0.175), shape: .capsuleH, side: .right),

            // 两只摇杆并排在下方中间 —— PS 的对称布局
            .init(id: 11, label: L("左摇杆按下"), pos: .init(x: 0.352, y: 0.560),
                  size: .init(width: 0.145, height: 0.210), shape: .circle, side: .left),
            .init(id: 12, label: L("右摇杆按下"), pos: .init(x: 0.648, y: 0.560),
                  size: .init(width: 0.145, height: 0.210), shape: .circle, side: .right),
            .init(id: StickChannel.right.anchorID, label: L("右摇杆方向"),
                  pos: .init(x: 0.648, y: 0.560),
                  size: .init(width: 0.145, height: 0.210), shape: .circle, side: .right),

            .init(id: 13, label: "PS", pos: .init(x: 0.500, y: 0.660),
                  size: .init(width: 0.048, height: 0.070), shape: .circle, side: .left),
        ]
        if mute {
            a.append(.init(id: 15, label: L("静音"), pos: .init(x: 0.500, y: 0.775),
                           size: .init(width: 0.055, height: 0.048),
                           shape: .capsuleH, side: .right))
        }
        return DeviceArt(anchors: a, aspect: 1.52, railSide: nil,
                         style: .playstation, hatLabel: L("十字键"))
    }
}

// MARK: - 手柄本体绘制

/// 用矢量画而不是贴产品照: 照片有版权/商标问题不能分发, 而且是死的 ——
/// 矢量能让单颗按键跟着实时输入点亮。
struct DeviceBody: View {
    let art: DeviceArt
    let bound: Set<Int>
    let highlighted: Int?
    let liveDir: (StickChannel, String)?

    @Environment(\.colorScheme) private var scheme

    private let bodyColor = Color(red: 0.16, green: 0.17, blue: 0.19)

    /// Xelu's CC0 Xbox Series diagram is close enough to the Elite Series 2
    /// front shell that it makes a much better geometric base than a hand-
    /// approximated silhouette. JoyCoding still owns every live overlay, so
    /// the imported artwork never dictates input behavior.
    ///
    /// The source art is white line work. Recoloring it once per appearance
    /// keeps the line weight readable on both hero surfaces: dark ink on the
    /// light tile, near-white ink on the dark one.
    private static func xboxVector(ink: String) -> NSImage? {
        let bundle = Bundle.main
        let urls = [
            bundle.url(forResource: "XboxSeriesController", withExtension: "svg",
                       subdirectory: "ControllerArt"),
            bundle.url(forResource: "XboxSeriesController", withExtension: "svg"),
        ]
        guard let url = urls.compactMap({ $0 }).first,
              var svg = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }
        svg = svg.replacingOccurrences(of: "#ffffff", with: ink,
                                       options: .caseInsensitive)
        return NSImage(data: Data(svg.utf8))
    }

    private static let xboxVectorLight: NSImage? = xboxVector(ink: "#3c3c40")
    private static let xboxVectorDark: NSImage? = xboxVector(ink: "#e3e4e9")

    private var isXbox: Bool {
        art.style == .xbox || art.style == .xboxElite2
    }

    private var dark: Bool { scheme == .dark }

    private var xboxVectorImage: NSImage? {
        dark ? Self.xboxVectorDark : Self.xboxVectorLight
    }

    private var usesXboxVector: Bool {
        isXbox && xboxVectorImage != nil
    }

    /// 叠加控件的表面色。线稿是空心的, 所以这些键帽要自己带底色才盖得住
    /// 下面的线; 底色必须跟随明暗, 否则深色模式下会出现一排白斑。
    private var controlSurface: Color {
        dark ? Color(white: 0.20) : .white
    }

    private var controlEdge: Color {
        dark ? Color.white.opacity(0.32) : Color.black.opacity(0.30)
    }

    private var controlGlyph: Color {
        dark ? Color.white.opacity(0.62) : Color.black.opacity(0.45)
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .topLeading) {
                if usesXboxVector {
                    xboxArtwork(w: w, h: h)
                    if let dpad = art.anchors.first(where: {
                        StickChannel.from(anchorID: $0.id) == .hat
                    }) {
                        xboxDpadOverlay(dpad, w: w, h: h)
                    }
                    ForEach(art.anchors.filter {
                        StickChannel.from(anchorID: $0.id) == nil
                    }) { a in
                        xboxControlOverlay(a, w: w, h: h)
                    }
                } else {
                    shoulders(w: w, h: h)
                    shell(w: w, h: h)
                    rail(w: w, h: h)
                    controllerDetails(w: w, h: h)
                    if let dpad = art.anchors.first(where: {
                        StickChannel.from(anchorID: $0.id) == .hat
                    }), art.style != .joycon {
                        dpadView(dpad, w: w, h: h)
                    }
                    ForEach(art.anchors.filter {
                        $0.id != 15 && $0.id != 16 && StickChannel.from(anchorID: $0.id) == nil
                    }) { a in
                        anchorView(a, w: w, h: h)
                    }
                }
                // 静止时不画永久的大箭头。只有方向输入发生时才在对应摇杆附近
                // 显示一个紧凑指示；D-pad 自己的按键帽负责显示 hat 通道。
                ForEach(art.anchors.filter {
                    guard let ch = StickChannel.from(anchorID: $0.id) else { return false }
                    return ch != .hat && liveDir?.0 == ch
                }) { a in
                    stickArrows(a, w: w, h: h, on: liveDir?.1)
                }
            }
        }
    }

    @ViewBuilder
    private func xboxArtwork(w: CGFloat, h: CGFloat) -> some View {
        if let image = xboxVectorImage {
            ZStack {
                // 线稿本身是空心的。在轮廓里垫一层很浅的机身色, 手柄才有"面";
                // 这条路径是照着同一张 CC0 线稿标定的, 所以能对上边界。
                xboxPath(w, h)
                    .fill(LinearGradient(
                        colors: dark ? [Color(white: 0.255), Color(white: 0.165)]
                                     : [Color(white: 0.995), Color(white: 0.945)],
                        startPoint: .top, endPoint: .bottom))
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .frame(width: w, height: h)
            }
            .frame(width: w, height: h)
        }
    }

    /// The source diagram depicts a Series controller's cross D-pad. The
    /// connected Elite Series 2 has the circular faceted metal dish, so this
    /// opaque live overlay both corrects the hardware model and covers the
    /// source D-pad without changing the source asset. The machined dish is
    /// brushed metal, so it darkens with the surrounding surface.
    private func xboxDpadOverlay(_ a: ButtonAnchor, w: CGFloat, h: CGFloat) -> some View {
        let side = max(28, a.size.width * w * 1.10)
        let active = liveDir?.0 == .hat ? liveDir?.1 : nil
        let metal: [Color] = dark
            ? [0.50, 0.33, 0.44, 0.31, 0.50].map { Color(white: $0) }
            : [0.93, 0.80, 0.90, 0.78, 0.93].map { Color(white: $0) }
        return ZStack {
            Circle()
                .fill(AngularGradient(colors: metal, center: .center))
            EliteDPadFacetLines()
                .stroke(Color.black.opacity(dark ? 0.24 : 0.10), lineWidth: 1)
            Circle()
                .stroke(Color.black.opacity(dark ? 0.50 : 0.30), lineWidth: 1.2)
            Circle()
                .fill(Color.black.opacity(dark ? 0.26 : 0.10))
                .frame(width: side * 0.29, height: side * 0.29)
            ForEach([
                ("up", "chevron.up", CGPoint(x: 0.50, y: 0.17)),
                ("right", "chevron.right", CGPoint(x: 0.83, y: 0.50)),
                ("down", "chevron.down", CGPoint(x: 0.50, y: 0.83)),
                ("left", "chevron.left", CGPoint(x: 0.17, y: 0.50)),
            ], id: \.0) { key, icon, pos in
                Image(systemName: icon)
                    .font(.system(size: side * 0.085, weight: .bold))
                    .foregroundStyle(active == key ? Color.accentColor
                                                   : Color.black.opacity(dark ? 0.62 : 0.45))
                    .shadow(color: active == key ? Color.accentColor.opacity(0.65) : .clear,
                            radius: 3)
                    .position(x: pos.x * side, y: pos.y * side)
            }
        }
        .frame(width: side, height: side)
        .shadow(color: .black.opacity(0.18), radius: 2, y: 1.5)
        .position(x: a.pos.x * w, y: a.pos.y * h)
        .frame(width: w, height: h)
    }

    /// Preserve the source diagram at rest. We only replace controls that are
    /// physically different on Elite 2 (Profile and D-pad), restore Xbox's
    /// colored ABXY legends, or paint a transient input highlight.
    @ViewBuilder
    private func xboxControlOverlay(_ a: ButtonAnchor, w: CGFloat, h: CGFloat) -> some View {
        let cx = a.pos.x * w, cy = a.pos.y * h
        let bw = a.size.width * w, bh = a.size.height * h
        let hot = highlighted == a.id
        let isFace = ["A", "B", "X", "Y"].contains(a.label)
        let stickChannel: StickChannel? = a.id == 9 ? .left : (a.id == 10 ? .right : nil)
        let moving = stickChannel != nil && liveDir?.0 == stickChannel

        ZStack {
            if isFace {
                Circle()
                    .fill(hot ? Color.accentColor.opacity(0.85) : controlSurface)
                    .overlay(Circle().stroke(hot ? Color.accentColor : controlEdge,
                                             lineWidth: 1.1))
                    .frame(width: bw, height: bw)
                    .shadow(color: .black.opacity(dark ? 0.30 : 0.10), radius: 1, y: 1)
                Text(a.label)
                    .font(.system(size: max(8, bw * 0.52), weight: .bold, design: .rounded))
                    .foregroundStyle(hot ? Color.white : faceLegend(a.label))
            } else if a.kind == .profile {
                Capsule()
                    .fill(hot ? Color.accentColor.opacity(0.85) : controlSurface)
                    .overlay(Capsule().stroke(hot ? Color.accentColor : controlEdge,
                                              lineWidth: 1))
                    .frame(width: bw * 1.42, height: bw * 0.68)
                    .shadow(color: .black.opacity(dark ? 0.30 : 0.10), radius: 1, y: 1)
                HStack(spacing: max(1.5, bw * 0.10)) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle().fill(hot ? Color.white : controlGlyph)
                            .frame(width: max(2, bw * 0.10), height: max(2, bw * 0.10))
                    }
                }
            } else if hot || moving {
                if a.kind == .stick {
                    Circle()
                        .fill(Color.accentColor.opacity(hot ? 0.62 : 0.34))
                        .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
                        .frame(width: bw * 0.78, height: bw * 0.78)
                        .offset(stickOffset(a, amount: bw * 0.07))
                } else if a.shape == .circle {
                    Circle()
                        .fill(Color.accentColor.opacity(0.55))
                        .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
                        .frame(width: bw, height: bw)
                } else {
                    Capsule()
                        .fill(Color.accentColor.opacity(0.55))
                        .overlay(Capsule().stroke(Color.accentColor, lineWidth: 2))
                        .frame(width: bw, height: bh)
                }
            }
        }
        .shadow(color: (hot || moving) ? Color.accentColor.opacity(0.45) : .clear,
                radius: 4)
        .position(x: cx, y: cy)
        .frame(width: w, height: h)
    }

    // 机身: 滑轨那侧是直边, 外侧是大圆角 —— Joy-Con 的辨识特征
    /// Pro 手柄轮廓: 顶部两肩、中间收窄、两个握把向下张开。
    /// 用归一化控制点描一遍, 换尺寸自动跟着缩放。
    private func proPath(_ w: CGFloat, _ h: CGFloat) -> Path {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { .init(x: x * w, y: y * h) }
        var p = Path()
        p.move(to: pt(0.30, 0.030))
        p.addQuadCurve(to: pt(0.70, 0.030), control: pt(0.50, 0.105))   // 顶部中间微凹
        p.addCurve(to: pt(0.965, 0.300),                                // 右肩
                   control1: pt(0.88, 0.020), control2: pt(0.975, 0.130))
        p.addCurve(to: pt(0.845, 0.945),                                // 右握把外侧
                   control1: pt(0.995, 0.640), control2: pt(0.955, 0.905))
        p.addCurve(to: pt(0.655, 0.720),                                // 右握把内侧
                   control1: pt(0.745, 0.995), control2: pt(0.700, 0.870))
        p.addQuadCurve(to: pt(0.345, 0.720), control: pt(0.500, 0.605)) // 底部中间
        p.addCurve(to: pt(0.155, 0.945),                                // 左握把内侧
                   control1: pt(0.300, 0.870), control2: pt(0.255, 0.995))
        p.addCurve(to: pt(0.035, 0.300),                                // 左握把外侧
                   control1: pt(0.045, 0.905), control2: pt(0.005, 0.640))
        p.addCurve(to: pt(0.30, 0.030),                                 // 左肩
                   control1: pt(0.025, 0.130), control2: pt(0.12, 0.020))
        p.closeSubpath()
        return p
    }

    /// Xbox 的握把比 Pro 更圆、更向外张，顶部中央也有明显的浅凹。
    /// 单独画一条轮廓，避免所有横向手柄都共用同一个笨重的外形。
    private func xboxPath(_ w: CGFloat, _ h: CGFloat) -> Path {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { .init(x: x * w, y: y * h) }
        var p = Path()
        // Calibrated against the CC0 Xelu outline: low straight center deck,
        // steep shoulders, long grips, and the shallow lower-center bridge.
        p.move(to: pt(0.135, 0.170))
        p.addCurve(to: pt(0.285, 0.105),
                   control1: pt(0.180, 0.125), control2: pt(0.240, 0.095))
        p.addCurve(to: pt(0.355, 0.170),
                   control1: pt(0.315, 0.100), control2: pt(0.325, 0.155))
        p.addLine(to: pt(0.645, 0.170))
        p.addCurve(to: pt(0.715, 0.105),
                   control1: pt(0.675, 0.155), control2: pt(0.685, 0.100))
        p.addCurve(to: pt(0.865, 0.170),
                   control1: pt(0.760, 0.095), control2: pt(0.820, 0.125))
        p.addCurve(to: pt(0.965, 0.505),
                   control1: pt(0.915, 0.235), control2: pt(0.950, 0.365))
        p.addCurve(to: pt(0.900, 0.950),
                   control1: pt(0.995, 0.705), control2: pt(0.975, 0.865))
        p.addCurve(to: pt(0.785, 0.970),
                   control1: pt(0.865, 0.990), control2: pt(0.825, 0.995))
        p.addCurve(to: pt(0.690, 0.850),
                   control1: pt(0.755, 0.945), control2: pt(0.725, 0.885))
        p.addCurve(to: pt(0.310, 0.850),
                   control1: pt(0.610, 0.815), control2: pt(0.390, 0.815))
        p.addCurve(to: pt(0.215, 0.970),
                   control1: pt(0.275, 0.885), control2: pt(0.245, 0.945))
        p.addCurve(to: pt(0.100, 0.950),
                   control1: pt(0.175, 0.995), control2: pt(0.135, 0.990))
        p.addCurve(to: pt(0.035, 0.505),
                   control1: pt(0.025, 0.865), control2: pt(0.005, 0.705))
        p.addCurve(to: pt(0.135, 0.170),
                   control1: pt(0.050, 0.365), control2: pt(0.085, 0.235))
        p.closeSubpath()
        return p
    }

    /// PS 手柄轮廓: 顶部平直、两侧握把更长更外撇, 整体比 Pro 更宽扁
    private func psPath(_ w: CGFloat, _ h: CGFloat) -> Path {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { .init(x: x * w, y: y * h) }
        var p = Path()
        p.move(to: pt(0.335, 0.035))
        p.addQuadCurve(to: pt(0.665, 0.035), control: pt(0.500, 0.020))  // 顶部近乎平直
        p.addCurve(to: pt(0.975, 0.275),
                   control1: pt(0.875, 0.030), control2: pt(0.985, 0.120))
        p.addCurve(to: pt(0.800, 0.960),                                  // 右握把外侧
                   control1: pt(0.965, 0.640), control2: pt(0.915, 0.930))
        p.addCurve(to: pt(0.610, 0.700),                                  // 右握把内侧
                   control1: pt(0.700, 0.995), control2: pt(0.655, 0.845))
        p.addQuadCurve(to: pt(0.390, 0.700), control: pt(0.500, 0.640))
        p.addCurve(to: pt(0.200, 0.960),
                   control1: pt(0.345, 0.845), control2: pt(0.300, 0.995))
        p.addCurve(to: pt(0.025, 0.275),
                   control1: pt(0.085, 0.930), control2: pt(0.035, 0.640))
        p.addCurve(to: pt(0.335, 0.035),
                   control1: pt(0.015, 0.120), control2: pt(0.125, 0.030))
        p.closeSubpath()
        return p
    }

    private func bodyPath(_ w: CGFloat, _ h: CGFloat) -> Path {
        if art.style == .playstation { return psPath(w, h) }
        if art.style == .xbox || art.style == .xboxElite2 { return xboxPath(w, h) }
        if art.style == .proController {
            return proPath(w, h)
        }
        let rS = w * 0.12, rB = w * 0.46
        var p = Path()
        // 滑轨在右边时整条机身左右翻一下 (左 Joy-Con)
        if art.railSide == .right {
            var q = Path()
            q.move(to: .init(x: w - rS, y: 0))
            q.addLine(to: .init(x: rB, y: 0))
            q.addQuadCurve(to: .init(x: 0, y: rB), control: .init(x: 0, y: 0))
            q.addLine(to: .init(x: 0, y: h - rB))
            q.addQuadCurve(to: .init(x: rB, y: h), control: .init(x: 0, y: h))
            q.addLine(to: .init(x: w - rS, y: h))
            q.addQuadCurve(to: .init(x: w, y: h - rS), control: .init(x: w, y: h))
            q.addLine(to: .init(x: w, y: rS))
            q.addQuadCurve(to: .init(x: w - rS, y: 0), control: .init(x: w, y: 0))
            q.closeSubpath()
            return q
        }
        p.move(to: .init(x: rS, y: 0))
        p.addLine(to: .init(x: w - rB, y: 0))
        p.addQuadCurve(to: .init(x: w, y: rB), control: .init(x: w, y: 0))
        p.addLine(to: .init(x: w, y: h - rB))
        p.addQuadCurve(to: .init(x: w - rB, y: h), control: .init(x: w, y: h))
        p.addLine(to: .init(x: rS, y: h))
        p.addQuadCurve(to: .init(x: 0, y: h - rS), control: .init(x: 0, y: h))
        p.addLine(to: .init(x: 0, y: rS))
        p.addQuadCurve(to: .init(x: rS, y: 0), control: .init(x: 0, y: 0))
        p.closeSubpath()
        return p
    }

    private func shell(w: CGFloat, h: CGFloat) -> some View {
        ZStack {
            bodyPath(w, h)
                .fill(LinearGradient(
                    stops: [
                        .init(color: Color(red: 0.24, green: 0.25, blue: 0.27), location: 0),
                        .init(color: bodyColor, location: 0.38),
                        .init(color: Color(red: 0.105, green: 0.11, blue: 0.12), location: 1),
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: .black.opacity(0.32), radius: w * 0.025, y: h * 0.025)
            bodyPath(w, h).stroke(Color.black.opacity(0.55), lineWidth: 2)
            bodyPath(w, h)
                .stroke(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.02)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1.2)
        }
        .frame(width: w, height: h)
    }

    @ViewBuilder
    private func controllerDetails(w: CGFloat, h: CGFloat) -> some View {
        if art.style == .xbox || art.style == .xboxElite2 {
            ZStack {
                // 中央面板的层次只靠材质差，不再用粗线把机身切碎。
                RoundedRectangle(cornerRadius: w * 0.035, style: .continuous)
                    .fill(Color.black.opacity(0.10))
                    .frame(width: w * 0.31, height: h * 0.34)
                    .position(x: w * 0.50, y: h * 0.29)
                RoundedRectangle(cornerRadius: w * 0.035, style: .continuous)
                    .stroke(Color.white.opacity(0.045), lineWidth: 1)
                    .frame(width: w * 0.31, height: h * 0.34)
                    .position(x: w * 0.50, y: h * 0.29)

                // Elite 握把的细点防滑纹理。
                ForEach(0..<5, id: \.self) { row in
                    ForEach(0..<4, id: \.self) { col in
                        Circle().fill(Color.white.opacity(0.055))
                            .frame(width: max(1.2, w * 0.004), height: max(1.2, w * 0.004))
                            .position(x: w * (0.115 + CGFloat(col) * 0.026 + CGFloat(row) * 0.008),
                                      y: h * (0.650 + CGFloat(row) * 0.048))
                        Circle().fill(Color.white.opacity(0.055))
                            .frame(width: max(1.2, w * 0.004), height: max(1.2, w * 0.004))
                            .position(x: w * (0.885 - CGFloat(col) * 0.026 - CGFloat(row) * 0.008),
                                      y: h * (0.650 + CGFloat(row) * 0.048))
                    }
                }
            }
            .frame(width: w, height: h)
        }
    }

    // 顶部肩键: ZR 在后, R 在前
    private func shoulders(w: CGFloat, h: CGFloat) -> some View {
        ZStack {
            if art.anchors.contains(where: { $0.id == 16 }) {
                Capsule()
                    .fill(fillColor(16).opacity(0.85))
                    .frame(width: w * 0.70, height: h * 0.022)
                    .position(x: w * 0.52, y: h * 0.008)
            }
            if art.anchors.contains(where: { $0.id == 15 }) {
                Capsule()
                    .fill(fillColor(15))
                    .frame(width: w * 0.86, height: h * 0.030)
                    .position(x: w * 0.50, y: h * 0.030)
            }
        }
        .frame(width: w, height: h)
    }

    // 滑轨: 贴合 Switch 主机那条平边, SL/SR 就长在上面
    private func rail(w: CGFloat, h: CGFloat) -> some View {
        ZStack {
            if let side = art.railSide {
                let rx = side == .right ? w * 0.957 : w * 0.043
                RoundedRectangle(cornerRadius: w * 0.03)
                    .fill(Color.black.opacity(0.35))
                    .frame(width: w * 0.085, height: h * 0.70)
                    .position(x: rx, y: h * 0.47)
                RoundedRectangle(cornerRadius: w * 0.03)
                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
                    .frame(width: w * 0.085, height: h * 0.70)
                    .position(x: rx, y: h * 0.47)
            }
        }
        .frame(width: w, height: h)
    }

    /// 摇杆四向指示。半径按摇杆本体算, 换手柄自动跟着走。
    private func stickArrows(_ stick: ButtonAnchor, w: CGFloat, h: CGFloat,
                             on liveKey: String?) -> some View {
        let cx = stick.pos.x * w, cy = stick.pos.y * h
        let r = stick.size.width * w * 0.52 + w * 0.035
        let offsets: [(String, CGFloat, CGFloat)] = [
            ("up", 0, -r), ("down", 0, r), ("left", -r, 0), ("right", r, 0),
        ]
        return ZStack {
            ForEach(offsets, id: \.0) { key, dx, dy in
                let on = liveKey == key
                Image(systemName: StickAnchor.arrow[key]!)
                    .font(.system(size: max(8, w * 0.036), weight: .bold))
                    .foregroundStyle(on ? Color.accentColor : Color.clear)
                    .shadow(color: on ? Color.accentColor.opacity(0.55) : .clear, radius: 3)
                    .position(x: cx + dx, y: cy + dy)
            }
        }
        .frame(width: w, height: h)
    }

    private func fillColor(_ id: Int) -> Color {
        if highlighted == id { return .accentColor }
        return bound.contains(id) ? Color.white.opacity(0.25) : Color.white.opacity(0.12)
    }

    private func faceLegend(_ label: String) -> Color {
        guard art.style == .xbox || art.style == .xboxElite2 else {
            return Color.white.opacity(0.70)
        }
        switch label {
        case "A": return Color(red: 0.35, green: 0.82, blue: 0.38)
        case "B": return Color(red: 0.96, green: 0.35, blue: 0.32)
        case "X": return Color(red: 0.32, green: 0.66, blue: 0.96)
        case "Y": return Color(red: 0.97, green: 0.78, blue: 0.25)
        default: return Color.white.opacity(0.65)
        }
    }

    private func stickOffset(_ a: ButtonAnchor, amount: CGFloat) -> CGSize {
        let ch: StickChannel? = {
            guard art.style == .xbox || art.style == .xboxElite2 else { return nil }
            if a.id == 9 { return .left }
            if a.id == 10 { return .right }
            return nil
        }()
        guard let ch, liveDir?.0 == ch else { return .zero }
        switch liveDir?.1 {
        case "up": return .init(width: 0, height: -amount)
        case "down": return .init(width: 0, height: amount)
        case "left": return .init(width: -amount, height: 0)
        case "right": return .init(width: amount, height: 0)
        default: return .zero
        }
    }

    private func dpadView(_ a: ButtonAnchor, w: CGFloat, h: CGFloat) -> some View {
        let side = max(24, a.size.width * w * 1.42)
        let active = liveDir?.0 == .hat ? liveDir?.1 : nil
        return ZStack {
            DPadCross()
                .fill(LinearGradient(
                    colors: [Color.white.opacity(0.22), Color.black.opacity(0.46)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(DPadCross().stroke(Color.white.opacity(0.14), lineWidth: 1))
            Circle().fill(Color.black.opacity(0.18))
                .frame(width: side * 0.34, height: side * 0.34)
            ForEach([
                ("up", "chevron.up", CGPoint(x: 0.50, y: 0.16)),
                ("right", "chevron.right", CGPoint(x: 0.84, y: 0.50)),
                ("down", "chevron.down", CGPoint(x: 0.50, y: 0.84)),
                ("left", "chevron.left", CGPoint(x: 0.16, y: 0.50)),
            ], id: \.0) { key, icon, pos in
                Image(systemName: icon)
                    .font(.system(size: side * 0.10, weight: .bold))
                    .foregroundStyle(active == key ? Color.accentColor : Color.white.opacity(0.38))
                    .position(x: pos.x * side, y: pos.y * side)
            }
        }
        .frame(width: side, height: side)
        .shadow(color: .black.opacity(0.28), radius: 2, y: 1)
        .position(x: a.pos.x * w, y: a.pos.y * h)
        .frame(width: w, height: h)
    }

    @ViewBuilder
    private func anchorView(_ a: ButtonAnchor, w: CGFloat, h: CGFloat) -> some View {
        let cx = a.pos.x * w, cy = a.pos.y * h
        let bw = a.size.width * w, bh = a.size.height * h
        let hot = highlighted == a.id
        let kind: AnchorKind = {
            if a.kind != .auto { return a.kind }
            if art.style == .playstation && a.id == 14 { return .touchpad }
            if a.id == 11 || a.id == 12 { return .stick }
            if a.id == 13 { return .home }
            if a.id == 14 { return .share }
            return .button
        }()

        ZStack {
            switch kind {
            case .stick:    // 摇杆: 底座 + 帽子, 做出立体感
                Circle().fill(Color.black.opacity(0.45))
                    .frame(width: bw, height: bw)
                Circle()
                    .fill(RadialGradient(
                        colors: [fillColor(a.id).opacity(0.9), fillColor(a.id).opacity(0.45)],
                        center: .init(x: 0.35, y: 0.3), startRadius: 1, endRadius: bw * 0.6))
                    .frame(width: bw * 0.74, height: bw * 0.74)
                    .offset(stickOffset(a, amount: bw * 0.075))
                Circle().stroke(Color.white.opacity(0.12), lineWidth: 1)
                    .frame(width: bw * 0.74, height: bw * 0.74)
                    .offset(stickOffset(a, amount: bw * 0.075))

            case .home, .share, .profile:    // 中央系统键: 外圈 + 图标
                Circle().stroke(Color.white.opacity(hot ? 0.9 : 0.20), lineWidth: 1.5)
                    .frame(width: bw * 1.55, height: bw * 1.55)
                Circle().fill(fillColor(a.id)).frame(width: bw, height: bw)
                Image(systemName: kind == .home ? "x.circle.fill"
                      : (kind == .profile ? "ellipsis" : "square.fill"))
                    .font(.system(size: max(5, bw * 0.5)))
                    .foregroundStyle(Color.black.opacity(0.5))

            case .touchpad:   // 触摸板: 大方块
                RoundedRectangle(cornerRadius: bh * 0.22)
                    .fill(fillColor(14)).frame(width: bw, height: bh)
                RoundedRectangle(cornerRadius: bh * 0.22)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    .frame(width: bw, height: bh)

            case .button where a.shape != .circle:   // SL/SR、肩键、扳机: 胶囊形
                Capsule().fill(fillColor(a.id)).frame(width: bw, height: bh)
                if bw > 22 {
                    Text(a.label).font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.5))
                }

            case .button, .system:    // 面键 + 加减号 / 系统键
                Circle().fill(fillColor(a.id)).frame(width: bw, height: bw)
                if a.label == "View" {
                    Image(systemName: "rectangle.on.rectangle")
                        .font(.system(size: max(5, bw * 0.38), weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.60))
                } else if a.label == "Menu" {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: max(5, bw * 0.46), weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.60))
                } else if a.label != "+" && a.label != "−" {
                    Text(a.label)
                        .font(.system(size: max(7, bw * 0.55), weight: .bold, design: .rounded))
                        .foregroundStyle(faceLegend(a.label))
                } else {
                    Image(systemName: a.label == "−" ? "minus" : "plus")
                        .font(.system(size: max(5, bw * 0.6), weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.5))
                }

            case .auto:
                EmptyView()
            }

            if hot {
                Circle().stroke(Color.accentColor, lineWidth: 2)
                    .frame(width: bw * 1.7, height: bw * 1.7)
                    .blur(radius: 3)
            }
        }
        .position(x: cx, y: cy)
        .frame(width: w, height: h)
    }
}

private struct DPadCross: Shape {
    func path(in rect: CGRect) -> Path {
        let points: [CGPoint] = [
            .init(x: 0.35, y: 0.00), .init(x: 0.65, y: 0.00),
            .init(x: 0.65, y: 0.35), .init(x: 1.00, y: 0.35),
            .init(x: 1.00, y: 0.65), .init(x: 0.65, y: 0.65),
            .init(x: 0.65, y: 1.00), .init(x: 0.35, y: 1.00),
            .init(x: 0.35, y: 0.65), .init(x: 0.00, y: 0.65),
            .init(x: 0.00, y: 0.35), .init(x: 0.35, y: 0.35),
        ]
        var p = Path()
        guard let first = points.first else { return p }
        p.move(to: .init(x: rect.minX + first.x * rect.width,
                         y: rect.minY + first.y * rect.height))
        for point in points.dropFirst() {
            p.addLine(to: .init(x: rect.minX + point.x * rect.width,
                                y: rect.minY + point.y * rect.height))
        }
        p.closeSubpath()
        return p
    }
}

/// Four diagonal seams give the Elite Series 2 dish its machined, faceted
/// read without turning it back into the ordinary plus-shaped Series D-pad.
private struct EliteDPadFacetLines: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let inset = min(rect.width, rect.height) * 0.12
        let corners = [
            CGPoint(x: rect.minX + inset, y: rect.minY + inset),
            CGPoint(x: rect.maxX - inset, y: rect.minY + inset),
            CGPoint(x: rect.maxX - inset, y: rect.maxY - inset),
            CGPoint(x: rect.minX + inset, y: rect.maxY - inset),
        ]
        var path = Path()
        for point in corners {
            path.move(to: center)
            path.addLine(to: point)
        }
        return path
    }
}
