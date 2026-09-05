import SwiftUI
import AppKit

/// 表格列宽。表头和每一行共用同一组常量 —— 差一点就会看出错位。
private enum MapMetrics {
    static let sidebar: CGFloat = 352
    static let label: CGFloat = 168
    static let status: CGFloat = 68
    static let rowH: CGFloat = 34
    static let hPad: CGFloat = 16
    static let colGap: CGFloat = 10
    static let indent: CGFloat = 18
    static let cellInset: CGFloat = 7
    static let heroBox: CGFloat = 200
}

/// 按键映射页。左边固定一块手柄图和层列表, 右边是一张对齐的绑定表:
/// 一行一颗按键, 单击 / 双击 / 长按各占一列。
///
/// 之前是自适应卡片网格。同一行里卡片高度被最矮的那张定住, 方向卡的最后
/// 一行会被裁掉; 每张卡片又各自带边框和阴影, 二十来颗按键铺开只剩噪音,
/// 想"扫一眼看完现在每颗键是什么"反而做不到。表格把动作对齐成列, 一遍读完。
struct MappingView: View {
    @ObservedObject var store = ConfigStore.shared
    @ObservedObject var hid = HIDInput.shared
    @ObservedObject var batt = JoyConBattery.shared
    @Environment(\.colorScheme) private var scheme

    @State private var selectedID: String?
    @State private var hot: Int?              // 鼠标悬停高亮的按键
    @State private var hoveredDirection: (StickChannel, String)?
    @State private var hotCell: String?       // 悬停的那一格动作选择器
    @State private var actionPickerCell: String?
    @State private var recentlyChangedCell: String?
    @State private var hotLayer: String?
    @State private var pressed: Int?          // 手柄上真按下的键, 实时点亮
    @State private var learningStick = false
    @State private var liveDir: (StickChannel, String)?
    @State private var learningCh: StickChannel = .hat
    /// 当前编辑的层。"" = 基础层, 否则是 app 的 bundleID。
    @State private var layer = ""
    @State private var stickStep = 0
    @State private var stickDraft: [String: StickDir] = [:]

    /// Deterministic visual-QA hook. This is deliberately launch-only and the
    /// toolbar labels it as a preview, so screenshots can exercise the exact
    /// installed mapping UI without claiming a sleeping controller is live.
    private static let uiPreviewDevice: ConnectedDevice? = {
        guard ProcessInfo.processInfo.environment["JOYCODING_UI_PREVIEW"] == "xboxElite2"
        else { return nil }
        return ConnectedDevice(vendorID: XboxHID.vendorID,
                               productID: XboxHID.elite2ProductID,
                               name: "Xbox Elite Series 2")
    }()

    /// (方向键, 默认动作)。提示文案按设备现生成 —— Joy-Con 上是摇杆要"推",
    /// Pro 手柄上这个通道其实是十字键, 得说"按"。
    private let stickWizard: [(String, String)] = [
        ("up",    "scrollUp"),
        ("down",  "scrollDown"),
        ("left",  "sessionPrev"),
        ("right", "sessionNext"),
    ]

    /// 通道在这只手柄上叫什么 —— 用设备图锚点上的名字, 比枚举里的通用名准确
    /// (Joy-Con 是"摇杆方向", Pro 手柄主通道是"十字键 / 左摇杆")
    private func chLabel(_ ch: StickChannel) -> String {
        art?.anchors.first { $0.id == ch.anchorID }?.label ?? ch.label
    }

    /// 通道徽标。三个通道共用一个图标时表格里三行长得一模一样,
    /// 反而得读完文字才知道是哪根杆。
    private func chIcon(_ ch: StickChannel) -> String {
        switch ch {
        case .hat:   return hatLabel == L("十字键") ? "dpad.fill" : "l.joystick.fill"
        case .left:  return "l.joystick.fill"
        case .right: return "r.joystick.fill"
        }
    }

    /// 这只手柄有哪些方向通道
    private var channels: [StickChannel] {
        guard let a = art else { return [.hat] }
        return a.anchors.compactMap { StickChannel.from(anchorID: $0.id) }
    }

    /// 这只手柄的方向通道叫什么: Joy-Con = 摇杆, Pro = 十字键
    private var hatLabel: String {
        guard let d = device else { return L("摇杆") }
        return DeviceArt.art(vendor: d.vendorID, product: d.productID).hatLabel
    }

    private func stickPrompt(_ ch: StickChannel, _ i: Int) -> String {
        let dir = [L("上"), L("下"), L("左"), L("右")][min(i, 3)]
        if ch == .right { return L("把右摇杆推向【%@】", dir) }
        if ch == .left { return L("把左摇杆推向【%@】", dir) }
        return hatLabel == L("十字键")
            ? L("按十字键或推左摇杆【%@】", dir) : L("把摇杆推向【%@】", dir)
    }

    private var device: ConnectedDevice? {
        hid.devices.first { $0.id == selectedID } ?? hid.devices.first
            ?? Self.uiPreviewDevice
    }
    private var isUIPreview: Bool {
        hid.devices.isEmpty && Self.uiPreviewDevice != nil
    }
    private var profile: DeviceProfile? {
        guard let d = device else { return nil }
        return store.config.devices.first { $0.id == d.id }
    }
    private var art: DeviceArt? {
        guard let d = device else { return nil }
        let a = DeviceArt.art(vendor: d.vendorID, product: d.productID)
        return a.anchors.isEmpty ? nil : a
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 1040, minHeight: 640)
        .onAppear {
            selectedID = hid.devices.first?.id ?? Self.uiPreviewDevice?.id
            watchPresses()
        }
        .onDisappear { hid.setTestMode(false); stopWatching() }
        .onChange(of: hid.devices.map(\.id)) { _ in
            if selectedID == nil { selectedID = hid.devices.first?.id }
        }
        .onChange(of: layer) { _ in actionPickerCell = nil }
    }

    @ViewBuilder
    private var content: some View {
        if let d = device, let art {
            HStack(spacing: 0) {
                sidebar(d, art)
                Divider()
                table(d, art)
            }
        } else {
            emptyState
        }
    }

    // MARK: - 顶栏

    private var header: some View {
        HStack(spacing: 10) {
            identity
            Spacer(minLength: 12)
            if !KeySynth.hasAccessibility { axButton }
            if let d = device, !isUIPreview { learnControl(d) }
            if hid.testMode {
                Text(L("只点亮，不执行"))
                    .font(.system(size: 11)).foregroundStyle(.orange)
            }
            testToggle
        }
        .padding(.horizontal, MapMetrics.hPad)
        .padding(.vertical, 9)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// 设备身份。只有一只手柄时不摆下拉框 —— 下拉里只有一项纯属噪音。
    @ViewBuilder
    private var identity: some View {
        HStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.accentColor.opacity(0.15))
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 26, height: 26)

            if hid.devices.count > 1 {
                Picker("", selection: Binding(
                    get: { selectedID ?? hid.devices.first?.id ?? "" },
                    set: { selectedID = $0 })) {
                    ForEach(hid.devices) { d in Text(d.name).tag(d.id) }
                }
                .labelsHidden().pickerStyle(.menu).fixedSize()
            } else if let d = device {
                VStack(alignment: .leading, spacing: 0) {
                    Text(d.name).font(.system(size: 13, weight: .semibold))
                    Text(d.id).font(.system(size: 10)).foregroundStyle(.tertiary)
                }
            } else {
                Text(L("未连接手柄"))
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
            }

            if isUIPreview {
                statusPill(.orange, "UI preview")
            } else if !hid.devices.isEmpty {
                statusPill(.green, L("已连接"))
                battery
            }
        }
    }

    @ViewBuilder
    private var battery: some View {
        if let d = device, let pct = batt.levels[d.id] {
            HStack(spacing: 4) {
                Image(systemName: batt.charging[d.id] == true
                      ? "battery.100.bolt" : JoyConBattery.symbol(pct))
                Text("\(pct)%").monospacedDigit()
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(pct <= 20 ? Color.orange : Color.secondary)
            .help(L("Joy-Con 电量"))
        }
    }

    private var axButton: some View {
        Button {
            NSWorkspace.shared.open(URL(string:
              "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        } label: {
            Label(L("辅助功能未授权"), systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(.orange)
        }
        .buttonStyle(.plain)
        .help(L("勾选后必须重启 JoyCoding 才生效"))
    }

    private var testToggle: some View {
        Toggle(isOn: Binding(
            get: { hid.testMode },
            set: { hid.setTestMode($0) })) {
            Label(L("测试模式"), systemImage: "hand.raised.fill")
                .font(.system(size: 12, weight: .medium))
        }
        .toggleStyle(.button)
        .tint(hid.testMode ? .orange : .accentColor)
        .help(L("测试模式说明"))
    }

    private func statusPill(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(text).font(.system(size: 10.5, weight: .semibold))
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.14)))
        .foregroundStyle(color)
    }

    @ViewBuilder
    private func learnControl(_ d: ConnectedDevice) -> some View {
        if learningStick {
            Text(stickStep < stickWizard.count
                 ? stickPrompt(learningCh, stickStep) : "")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.accentColor)
            Button(L("取消")) { endStick() }.controlSize(.small)
        } else {
            let chs = channels
            if chs.count <= 1 {
                Button { beginStick(d, chs.first ?? .hat) } label: {
                    Label(L("学习「%@」", chLabel(chs.first ?? .hat)),
                          systemImage: "wand.and.stars").font(.system(size: 12))
                }
            } else {
                Menu {
                    ForEach(chs, id: \.self) { ch in
                        Button(L("学习「%@」", chLabel(ch))) { beginStick(d, ch) }
                    }
                } label: {
                    Label(L("学习方向"), systemImage: "wand.and.stars")
                        .font(.system(size: 12))
                }
                .fixedSize()
            }
        }
    }

    // MARK: - 左栏: 手柄图 + 层

    private func sidebar(_ d: ConnectedDevice, _ art: DeviceArt) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            heroPanel(art)
            focusLine(art)
            Text(L("映射层"))
                .font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
                .padding(.top, 4)
            ScrollView(.vertical) {
                VStack(spacing: 2) {
                    layerRow("", L("基础"))
                    ForEach(store.config.targetApps, id: \.self) { app in
                        layerRow(app, AppName.of(app))
                    }
                }
            }
            .frame(maxHeight: .infinity)
            if !layer.isEmpty { layerHint }
        }
        .padding(MapMetrics.hPad)
        .frame(width: MapMetrics.sidebar, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// The tile follows the system appearance. Elite's black product artwork
    /// keeps its material colors; the other diagrams adapt their line colors.
    private func heroPanel(_ art: DeviceArt) -> some View {
        let boxW = MapMetrics.sidebar - MapMetrics.hPad * 2 - 28
        let w = min(boxW, MapMetrics.heroBox * art.aspect)
        let bound = Set(art.anchors.map(\.id).filter {
            !(profile?.binding(button: $0, app: layer)?.isEmpty ?? true)
        })
        let h = w / art.aspect
        return ZStack {
            // 落地阴影。线稿是空心的, 没有这一笔手柄就像浮在纸面上的一圈线。
            Ellipse()
                .fill(Color.black.opacity(scheme == .dark ? 0.34 : 0.13))
                .frame(width: w * 0.62, height: h * 0.07)
                .blur(radius: 7)
                .offset(y: h * 0.47)
            DeviceBody(art: art, bound: bound,
                       highlighted: pressed ?? hot, liveDir: liveDir ?? hoveredDirection)
                .frame(width: w, height: h)
        }
            .frame(width: w, height: h)
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: MapMetrics.heroBox + 28)
            .background(heroSurface)
    }

    private var heroSurface: some View {
        let dark = scheme == .dark
        return RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(LinearGradient(
                colors: dark ? [Color(white: 0.17), Color(white: 0.10)]
                             : [Color(white: 1.00), Color(white: 0.94)],
                startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(dark ? 0.16 : 0.08), lineWidth: 1))
            .shadow(color: .black.opacity(dark ? 0.30 : 0.09), radius: 4, y: 2)
    }

    /// 手柄图下面一行随动说明: 悬停/按下哪颗键就说那颗键现在绑了什么。
    /// 高度写死, 免得内容变化时整栏跟着跳。
    private func focusLine(_ art: DeviceArt) -> some View {
        let a = art.anchors.first { $0.id == (pressed ?? hot) }
        return HStack(spacing: 6) {
            if let a {
                Text(a.label).font(.system(size: 11.5, weight: .semibold))
                Text(focusSummary(a))
                    .font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
            } else {
                Text(L("鼠标移到某一行，手柄图上会点亮对应按键"))
                    .font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 14)
    }

    private func focusSummary(_ a: ButtonAnchor) -> String {
        if let ch = StickChannel.from(anchorID: a.id) {
            return (profile?.sticks[ch.rawValue]?.isEmpty ?? true) ? L("未学习") : ch.label
        }
        guard let id = profile?.binding(button: a.id, app: layer)?.tap,
              let name = Actions.action(for: id)?.name else { return L("未设置") }
        return name
    }

    private func layerRow(_ id: String, _ title: String) -> some View {
        let on = layer == id
        let count = id.isEmpty ? 0 : (profile?.overrides[id]?.buttons.count ?? 0)
        return Button { layer = id } label: {
            HStack(spacing: 7) {
                layerIcon(id)
                Text(title)
                    .font(.system(size: 12.5, weight: on ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .semibold)).monospacedDigit()
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(on ? Color.white.opacity(0.25)
                                                      : Color.primary.opacity(0.08)))
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(on ? Color.accentColor
                         : (hotLayer == id ? Color.primary.opacity(0.06) : Color.clear)))
            .foregroundStyle(on ? Color.white : Color.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hotLayer = $0 ? id : (hotLayer == id ? nil : hotLayer) }
    }

    @ViewBuilder
    private func layerIcon(_ id: String) -> some View {
        if id.isEmpty {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 11))
                .frame(width: 15, height: 15)
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable().frame(width: 15, height: 15)
        } else {
            Image(systemName: "app.dashed")
                .font(.system(size: 11)).foregroundStyle(.tertiary)
                .frame(width: 15, height: 15)
        }
    }

    private var layerHint: some View {
        let n = profile?.overrides[layer]?.buttons.count ?? 0
        return VStack(alignment: .leading, spacing: 3) {
            Text(n == 0 ? L("这一层还没有覆盖，按键都继承基础层")
                        : L("%@ 个按键在这一层被覆盖", String(n)))
            Text(L("灰色的动作继承自基础层"))
        }
        .font(.system(size: 10.5)).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "gamecontroller")
                .font(.system(size: 40)).foregroundStyle(.tertiary)
            Text(hid.devices.isEmpty ? L("没检测到手柄") : L("这个手柄还没有外观图"))
                .font(.system(size: 15, weight: .medium)).foregroundStyle(.secondary)
            Text(hid.devices.isEmpty
                 ? L("蓝牙配对后按一下手柄任意键唤醒它")
                 : L("按键仍可正常映射，只是画不出图形"))
                .font(.system(size: 12)).foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - 右栏: 绑定表

    private func table(_ d: ConnectedDevice, _ art: DeviceArt) -> some View {
        VStack(spacing: 0) {
            columnHeader
            Divider()
            ScrollView(.vertical) {
                // 用 VStack 而不是 LazyVStack: 一只手柄就二三十行, 懒加载省不到
                // 什么, 但配上 pinnedViews 会真出问题 —— 视口外的行只占位不渲染,
                // 表格末尾留一大片空白, 打开时还会莫名停在半行的位置。
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(sections(d, art), id: \.group) { section in
                        sectionHeader(section.title)
                        ForEach(section.anchors) { a in rowGroup(d, a) }
                    }
                }
                .padding(.bottom, 14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var columnHeader: some View {
        HStack(spacing: MapMetrics.colGap) {
            Text(L("按键")).frame(width: MapMetrics.label, alignment: .leading)
            columnTitle(L("单击"))
            columnTitle(L("双击"))
            columnTitle(L("长按"))
            if !layer.isEmpty {
                Color.clear.frame(width: MapMetrics.status, height: 1)
            }
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, MapMetrics.hPad)
        .padding(.vertical, 7)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// 动作列的表头要跟着单元格那 7pt 内缩走, 否则标题和值差一点点, 很显眼。
    private func columnTitle(_ t: String) -> some View {
        Text(t)
            .padding(.leading, MapMetrics.cellInset)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, MapMetrics.hPad)
            .padding(.top, 13).padding(.bottom, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .overlay(alignment: .bottom) { hairline }
    }

    private var hairline: some View {
        Rectangle()
            .fill(Color.primary.opacity(scheme == .dark ? 0.10 : 0.06))
            .frame(height: 1)
    }

    @ViewBuilder
    private func rowGroup(_ d: ConnectedDevice, _ a: ButtonAnchor) -> some View {
        if let ch = StickChannel.from(anchorID: a.id) {
            channelRow(d, a, ch)
            ForEach(DeviceProfile.dirKeys, id: \.self) { dir in dirRow(d, ch, dir) }
        } else if isReserved(d, a) {
            reservedRow(a, hardwareProfile: a.id == 12)
        } else {
            buttonRow(d, a)
        }
    }

    private func rowShell<C: View>(live: Bool, hovered: Bool,
                                   @ViewBuilder _ content: () -> C) -> some View {
        content()
            .padding(.horizontal, MapMetrics.hPad)
            .frame(height: MapMetrics.rowH)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowFill(live: live, hovered: hovered))
            .overlay(alignment: .bottom) { hairline }
    }

    private func rowFill(live: Bool, hovered: Bool) -> some View {
        ZStack(alignment: .leading) {
            Rectangle().fill(live ? Color.accentColor.opacity(scheme == .dark ? 0.22 : 0.10)
                                  : (hovered ? Color.primary.opacity(0.04) : Color.clear))
            if live { Rectangle().fill(Color.accentColor).frame(width: 2.5) }
        }
    }

    private func isReserved(_ d: ConnectedDevice, _ a: ButtonAnchor) -> Bool {
        d.vendorID == XboxHID.vendorID && d.productID == XboxHID.elite2ProductID
            && (a.id == 11 || a.id == 12)
    }

    // MARK: - 行

    private func buttonRow(_ d: ConnectedDevice, _ a: ButtonAnchor) -> some View {
        let b = profile?.binding(button: a.id, app: layer) ?? ButtonBinding()
        let overridden = !layer.isEmpty
            && (profile?.isOverridden(button: a.id, app: layer) ?? false)
        let inherited = !layer.isEmpty && !overridden
        return rowShell(live: pressed == a.id, hovered: hot == a.id) {
            HStack(spacing: MapMetrics.colGap) {
                labelCell(a, bound: !b.isEmpty)
                actionCell("\(a.id).tap", b.tap, dimmed: inherited,
                           target: "\(a.label) · \(L("单击"))") {
                    set(d, a.id, \.tap, $0)
                }
                actionCell("\(a.id).double", b.double, dimmed: inherited,
                           target: "\(a.label) · \(L("双击"))") {
                    set(d, a.id, \.double, $0)
                }
                actionCell("\(a.id).long", b.long, dimmed: inherited,
                           target: "\(a.label) · \(L("长按"))") {
                    set(d, a.id, \.long, $0)
                }
                if !layer.isEmpty {
                    overrideCell(overridden) { clearOverride(d, a.id) }
                }
            }
        }
        .onHover { hot = $0 ? a.id : (hot == a.id ? nil : hot) }
    }

    /// 方向通道自己一行, 只写通道名; 没学过就把「学习」按钮放在这里,
    /// 需要它的时候它就在眼前, 不用先去顶栏找。
    private func channelRow(_ d: ConnectedDevice, _ a: ButtonAnchor,
                            _ ch: StickChannel) -> some View {
        let learned = !(profile?.sticks[ch.rawValue]?.isEmpty ?? true)
        return rowShell(live: liveDir?.0 == ch, hovered: hot == a.id) {
            HStack(spacing: MapMetrics.colGap) {
                labelCell(a, bound: learned, emphasis: true, icon: chIcon(ch))
                if learned {
                    Spacer(minLength: 0)
                } else {
                    Button { beginStick(d, ch) } label: {
                        Label(L("学习「%@」", chLabel(ch)), systemImage: "wand.and.stars")
                            .font(.system(size: 11))
                    }
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .onHover { hot = $0 ? a.id : (hot == a.id ? nil : hot) }
    }

    /// 一个方向一行, 缩进挂在通道下面。方向没有双击/长按, 那两列留空 ——
    /// 画个占位符只会让人以为那里能点。
    private func dirRow(_ d: ConnectedDevice, _ ch: StickChannel,
                        _ dir: String) -> some View {
        let learned = profile?.stickDir(ch, dir) != nil
        let act = profile?.stickAction(ch, dir: dir, app: layer)
        let overridden = !layer.isEmpty
            && (profile?.isOverridden(ch, dir: dir, app: layer) ?? false)
        let live = liveDir?.0 == ch && liveDir?.1 == dir
        return rowShell(live: live, hovered: hoveredDirection?.0 == ch && hoveredDirection?.1 == dir) {
            HStack(spacing: MapMetrics.colGap) {
                dirLabelCell(dir, live: live, bound: act != nil)
                actionCell("\(ch.rawValue).\(dir)", act,
                           dimmed: !layer.isEmpty && !overridden,
                           target: "\(chLabel(ch)) · \(DeviceProfile.dirLabel[dir] ?? dir)",
                           unset: learned ? "—" : L("未学习"),
                           menuHint: learned ? nil : L("先点右上角学习「%@」", chLabel(ch))) {
                    setDir(d, ch, dir, $0)
                }
                Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                if !layer.isEmpty {
                    overrideCell(overridden) { setDir(d, ch, dir, nil) }
                }
            }
        }
        .onHover { inside in
            if inside {
                hot = ch.anchorID
                hoveredDirection = (ch, dir)
            } else {
                if hot == ch.anchorID { hot = nil }
                if hoveredDirection?.0 == ch && hoveredDirection?.1 == dir {
                    hoveredDirection = nil
                }
            }
        }
    }

    private func reservedRow(_ a: ButtonAnchor, hardwareProfile: Bool) -> some View {
        rowShell(live: false, hovered: hot == a.id) {
            HStack(spacing: MapMetrics.colGap) {
                labelCell(a, bound: false, icon: "lock.fill")
                Text(hardwareProfile
                     ? L("手柄硬件保留（切换板载配置）")
                     : L("macOS 系统保留（打开游戏控制器）"))
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                    .padding(.leading, MapMetrics.cellInset)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onHover { hot = $0 ? a.id : (hot == a.id ? nil : hot) }
    }

    // MARK: - 单元格

    private func labelCell(_ a: ButtonAnchor, bound: Bool, emphasis: Bool = false,
                           icon: String? = nil) -> some View {
        HStack(spacing: 7) {
            badge(a, bound: bound, icon: icon)
            Text(a.label)
                .font(.system(size: 12.5, weight: emphasis ? .semibold : .regular))
                .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .frame(width: MapMetrics.label, alignment: .leading)
    }

    /// 键位徽标: 短名直接写字 (A / LB), 长名用图标, 绑了动作的着主题色。
    private func badge(_ a: ButtonAnchor, bound: Bool, icon: String?) -> some View {
        let tint: Color = bound ? .accentColor : .secondary
        return ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(bound ? Color.accentColor.opacity(0.14)
                            : Color.primary.opacity(0.06))
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(tint)
            } else if a.kind == .profile {
                Image(systemName: "ellipsis")
                    .font(.system(size: 10, weight: .bold)).foregroundStyle(tint)
            } else if a.label.count <= 4 {
                Text(a.label)
                    .font(.system(size: a.label.count <= 2 ? 11 : 9,
                                  weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6).lineLimit(1)
                    .foregroundStyle(tint)
            } else {
                Image(systemName: a.kind == .stick ? "circle.circle" : "circle")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(tint)
            }
        }
        .frame(width: 26, height: 20)
    }

    private func dirLabelCell(_ dir: String, live: Bool, bound: Bool) -> some View {
        HStack(spacing: 7) {
            Color.clear.frame(width: MapMetrics.indent, height: 1)
            Image(systemName: StickAnchor.arrow[dir] ?? "arrow.up")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(live ? Color.white
                                      : (bound ? Color.accentColor : Color.secondary))
                .frame(width: 20, height: 20)
                .background(Circle().fill(live ? Color.accentColor
                    : (bound ? Color.accentColor.opacity(0.14)
                             : Color.primary.opacity(0.06))))
            Text(DeviceProfile.dirLabel[dir] ?? dir).font(.system(size: 12.5))
            Spacer(minLength: 0)
        }
        .frame(width: MapMetrics.label, alignment: .leading)
    }

    /// 一格动作。静止时只有文字, 悬停才出底色和箭头 —— 二十来行 × 三列的
    /// 输入框边框比内容还抢眼, 所以边框只在鼠标下出现。
    private func actionCell(_ key: String, _ current: String?, dimmed: Bool,
                            target: String, unset: String = "—", menuHint: String? = nil,
                            pick: @escaping (String?) -> Void) -> some View {
        let name = current.flatMap { Actions.action(for: $0)?.name }
        let hovered = hotCell == key
        let open = actionPickerCell == key
        let changed = recentlyChangedCell == key
        return Button {
            guard menuHint == nil else { return }
            actionPickerCell = open ? nil : key
        } label: {
            HStack(spacing: 4) {
                Text(name ?? unset)
                    .font(.system(size: 12.5))
                    .foregroundStyle(name == nil ? Color.secondary.opacity(0.55)
                                                 : (dimmed ? Color.secondary : Color.primary))
                    .lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
                Image(systemName: changed ? "checkmark.circle.fill" : "chevron.up.chevron.down")
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundStyle(changed ? Color.accentColor : Color.secondary)
                    .opacity((hovered || open || changed) ? 1 : 0.32)
            }
            .padding(.horizontal, MapMetrics.cellInset).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(changed ? Color.accentColor.opacity(0.10)
                              : ((hovered || open) ? Color.primary.opacity(0.07) : Color.clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .disabled(menuHint != nil)
        .help(menuHint ?? L("选择动作"))
        .accessibilityLabel(L("设置 %@", target))
        .popover(isPresented: Binding(
            get: { actionPickerCell == key },
            set: { if !$0 && actionPickerCell == key { actionPickerCell = nil } }
        ), arrowEdge: .trailing) {
            ActionPicker(current: current, layer: layer, target: target) { value in
                pick(value)
                actionPickerCell = nil
                withAnimation(.easeOut(duration: 0.16)) { recentlyChangedCell = key }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        if recentlyChangedCell == key { recentlyChangedCell = nil }
                    }
                }
            }
        }
        .onHover { hotCell = $0 ? key : (hotCell == key ? nil : hotCell) }
    }

    /// 只在这一层真被覆盖时才挂徽标。继承的行不写"继承"两个字 ——
    /// 二十行里十九行都写等于没写, 淡掉的动作文字已经说明了。
    private func overrideCell(_ overridden: Bool,
                              _ revert: @escaping () -> Void) -> some View {
        HStack(spacing: 0) {
            if overridden {
                Button(action: revert) {
                    Text(L("覆盖"))
                        .font(.system(size: 9.5, weight: .bold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .help(L("点一下恢复继承基础层"))
            }
            Spacer(minLength: 0)
        }
        .frame(width: MapMetrics.status, alignment: .leading)
    }

    // MARK: - 分区与排序

    private struct CardSection {
        let group: Int
        let title: String
        let anchors: [ButtonAnchor]
    }

    /// 0 肩键与扳机 / 1 面键 / 2 功能键 / 3 摇杆与十字键 / 4 背部拨片
    private func groupOf(_ a: ButtonAnchor, style: BodyStyle) -> Int {
        if a.kind == .paddle { return 4 }
        if StickChannel.from(anchorID: a.id) != nil { return 3 }
        if a.kind == .stick { return 3 }
        let isXbox = style == .xbox || style == .xboxElite2
        // Joy-Con / Pro 的摇杆按下没有显式 kind, 沿用 anchorView 的编号约定
        if !isXbox && (a.id == 11 || a.id == 12) { return 3 }
        switch a.kind {
        case .home, .share, .profile, .touchpad, .system: return 2
        default: break
        }
        if a.shape == .capsuleH && a.pos.y < 0.20 { return 0 }   // 顶部肩键/扳机
        if a.shape == .capsuleV { return 2 }                     // SL/SR、Create/Options
        if a.shape == .capsuleH && a.pos.y > 0.70 { return 2 }   // PS 静音键
        // 非 Xbox 的中央小圆键 (13=Home, 14=截图)
        if !isXbox && (a.id == 13 || a.id == 14) { return 2 }
        return 1
    }

    /// 组内按物理位置读: 从上到下, 同排从左到右。
    /// 摇杆组例外: 先「按下」(按 x), 再方向通道 (hat → 左 → 右)。
    private func gridRank(_ a: ButtonAnchor) -> Int {
        // Keep Xbox trigger and bumper pairs together even when a more
        // accurate front-view drawing puts their anchors in the same y band.
        if let shoulderRank = ["LT", "RT", "LB", "RB"].firstIndex(of: a.label) {
            return shoulderRank
        }
        if let ch = StickChannel.from(anchorID: a.id) {
            return 100 + (StickChannel.allCases.firstIndex(of: ch) ?? 0)
        }
        if a.kind == .stick { return 50 + Int(a.pos.x * 8) }
        return Int(a.pos.y / 0.12) * 10 + Int(a.pos.x * 8)
    }

    private func sections(_ d: ConnectedDevice, _ art: DeviceArt) -> [CardSection] {
        let style = art.style
        let titles = [L("肩键与扳机"), L("面键"), L("功能键"), L("摇杆与十字键"),
                      L("背部拨片")]
        return (0...4).compactMap { g in
            let items = art.anchors
                .filter { groupOf($0, style: style) == g }
                .sorted { gridRank($0) < gridRank($1) }
            return items.isEmpty ? nil : CardSection(group: g, title: titles[g], anchors: items)
        }
    }

    // MARK: - 摇杆

    private func setDir(_ d: ConnectedDevice, _ ch: StickChannel,
                        _ dir: String, _ action: String?) {
        mutate(d) { p in
            if layer.isEmpty {
                guard var sd = p.sticks[ch.rawValue]?[dir] else { return }
                sd.action = action
                p.sticks[ch.rawValue]?[dir] = sd
            } else {
                var ov = p.overrides[layer] ?? AppOverride()
                if let action { ov.sticks[ch.rawValue, default: [:]][dir] = action }
                else { ov.sticks[ch.rawValue]?.removeValue(forKey: dir) }
                if ov.isEmpty { p.overrides.removeValue(forKey: layer) } else { p.overrides[layer] = ov }
            }
        }
    }

    // MARK: - 实时输入

    /// 普通状态只旁观；测试模式是否拦截由 HIDInput 的统一安全门决定。
    private func watchPresses() {
        HIDInput.shared.previewHandler = { input in
            DispatchQueue.main.async {
                switch input {
                case .button(let n, let down):
                    pressed = down ? n : nil
                case .hat(let dir, let ch):
                    if let dir, let key = HIDInput.nearestKey(
                        dir, profile?.sticks[ch.rawValue] ?? [:]) {
                        liveDir = (ch, key)
                    } else if liveDir?.0 == ch {
                        liveDir = nil
                    }
                }
            }
        }
    }

    private func stopWatching() {
        HIDInput.shared.previewHandler = nil
        HIDInput.shared.captureHandler = nil
    }

    /// 学习摇杆期间才拦截, 结束立刻还回去
    private func beginStick(_ d: ConnectedDevice, _ ch: StickChannel) {
        stickStep = 0
        learningCh = ch
        stickDraft = [:]
        learningStick = true
        HIDInput.shared.captureHandler = { input in
            DispatchQueue.main.async {
                guard case .hat(let dir, let ch) = input, let dir, ch == learningCh,
                      stickStep < stickWizard.count else { return }
                let w = stickWizard[stickStep]
                // 同一个方向值不能学两次, 否则两个方向会打架
                guard !stickDraft.values.contains(where: { $0.hat == dir }) else { return }
                stickDraft[w.0] = StickDir(hat: dir, action: w.1)
                stickStep += 1
                if stickStep >= stickWizard.count {
                    let learned = stickDraft
                    mutate(d) { $0.sticks[ch.rawValue] = learned }
                    endStick()
                }
            }
        }
    }

    private func endStick() {
        learningStick = false
        stickDraft = [:]
        HIDInput.shared.captureHandler = nil
    }

    // MARK: - 配置读写

    private func clearOverride(_ d: ConnectedDevice, _ n: Int) {
        mutate(d) { p in
            p.overrides[layer]?.buttons.removeValue(forKey: String(n))
            if p.overrides[layer]?.isEmpty == true { p.overrides.removeValue(forKey: layer) }
        }
    }

    private func set(_ d: ConnectedDevice, _ n: Int,
                     _ path: WritableKeyPath<ButtonBinding, String?>, _ v: String?) {
        mutate(d) { p in
            if layer.isEmpty {
                p.buttons[String(n), default: .init()][keyPath: path] = v
            } else {
                // 首次覆盖: 先把基础层这颗键整个拷过来, 再改 ——
                // 覆盖以整颗按键为单位, 不做按手势继承
                var ov = p.overrides[layer] ?? AppOverride()
                var b = ov.buttons[String(n)] ?? p.buttons[String(n)] ?? ButtonBinding()
                b[keyPath: path] = v
                ov.buttons[String(n)] = b
                p.overrides[layer] = ov
            }
        }
    }

    private func mutate(_ d: ConnectedDevice, _ body: (inout DeviceProfile) -> Void) {
        if !store.config.devices.contains(where: { $0.id == d.id }) {
            store.config.devices.append(
                DeviceProfile(vendorID: d.vendorID, productID: d.productID, name: d.name))
        }
        guard let i = store.config.devices.firstIndex(where: { $0.id == d.id }) else { return }
        body(&store.config.devices[i])
        store.save()
    }
}
