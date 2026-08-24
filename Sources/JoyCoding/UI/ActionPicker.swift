import SwiftUI
import AppKit

/// A command-palette replacement for nested action menus. The picker answers
/// the useful questions in one view: what the action does, where it comes from,
/// and which shortcut it resolves to in the layer currently being edited.
struct ActionPicker: View {
    let current: String?
    let layer: String
    let target: String
    let onPick: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @FocusState private var searchFocused: Bool
    @State private var query = ""
    @State private var selectedID: String?
    @State private var keyboardScrollID: String?
    @State private var keyMonitor: Any?
    @State private var recentIDs = ActionPickerRecents.load()

    private struct PickerSection: Identifiable {
        let id: String
        let title: String
        let symbol: String?
        let actions: [ActionDef]
    }

    var body: some View {
        VStack(spacing: 0) {
            heading
            Divider().opacity(0.7)
            results
            Divider().opacity(0.7)
            footer
        }
        .frame(width: 530, height: 510)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            if let currentAction, isSelectable(currentAction) {
                selectedID = currentAction.id
            } else {
                selectedID = flatActions.first?.id
            }
            searchFocused = true
            installKeyMonitor()
        }
        .onDisappear { removeKeyMonitor() }
        .onChange(of: query) { _ in
            selectedID = flatActions.first?.id
        }
    }

    private var heading: some View {
        VStack(spacing: 10) {
            HStack(spacing: 9) {
                layerIcon
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("分配命令或动作"))
                        .font(.system(size: 13, weight: .semibold))
                    HStack(spacing: 4) {
                        ForEach(Array(targetParts.enumerated()), id: \.offset) { index, part in
                            if index > 0 {
                                Text("+").font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            shortcutBadge(part)
                        }
                        Text(layer.isEmpty ? L("基础层 · 所有 app")
                                           : L("%@ 专属映射", AppName.of(layer)))
                            .font(.system(size: 10.5)).foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if let currentAction {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                        Text(currentAction.name).lineLimit(1)
                    }
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 7).padding(.vertical, 4)
                    .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                    .frame(maxWidth: 190, alignment: .trailing)
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField(L("搜索命令或动作"), text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($searchFocused)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("⌘F")
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10).frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(scheme == .dark ? 0.10 : 0.055)))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1))
        }
        .padding(14)
    }

    private var targetParts: [String] {
        target.components(separatedBy: " · ").filter { !$0.isEmpty }
    }

    private func shortcutBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.primary.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1))
    }

    @ViewBuilder
    private var layerIcon: some View {
        if !layer.isEmpty,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: layer) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable().scaledToFit().frame(width: 27, height: 27)
        } else {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 27, height: 27)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.accentColor.opacity(0.13)))
        }
    }

    private var results: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    if sections.isEmpty {
                        emptyResults
                    } else {
                        ForEach(sections) { section in
                            Section {
                                ForEach(section.actions) { action in
                                    actionRow(action).id(action.id)
                                }
                            } header: {
                                sectionHeader(section)
                            }
                        }
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 6)
            }
            // Recreate the scroll container when search changes so every result set
            // starts at its top instead of inheriting an unrelated browse offset.
            .id(query.isEmpty ? "browse" : "search:\(query)")
            // Only keyboard navigation asks the list to follow the selection.
            // Mouse hover intentionally changes the highlight without scrolling:
            // otherwise rows moving beneath the pointer create a scroll/hover loop.
            .onChange(of: keyboardScrollID) { id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private func sectionHeader(_ section: PickerSection) -> some View {
        HStack(spacing: 5) {
            if let symbol = section.symbol {
                Image(systemName: symbol).font(.system(size: 9, weight: .semibold))
            }
            Text(section.title.uppercased())
                .font(.system(size: 9.5, weight: .bold))
                .tracking(0.45)
            Spacer()
            Text("\(section.actions.count)").monospacedDigit()
        }
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 8).padding(.top, 8).padding(.bottom, 4)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func actionRow(_ action: ActionDef) -> some View {
        let selected = selectedID == action.id
        let isCurrent = canonicalCurrent == action.id
        let selectable = isSelectable(action)
        return Button {
            choose(action)
        } label: {
            HStack(spacing: 10) {
                providerIcon(action, selected: selected)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(action.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(selected ? Color.white : Color.primary)
                            .lineLimit(1)
                        if isCurrent {
                            Text(L("当前"))
                                .font(.system(size: 8.5, weight: .bold))
                                .padding(.horizontal, 5).padding(.vertical, 1.5)
                                .background(Capsule().fill(selected
                                    ? Color.white.opacity(0.18)
                                    : Color.accentColor.opacity(0.13)))
                                .foregroundStyle(selected ? Color.white : Color.accentColor)
                        }
                    }
                    Text(metadata(for: action))
                        .font(.system(size: 10.5))
                        .foregroundStyle(selected ? Color.white.opacity(0.72) : Color.secondary)
                        .lineLimit(1).truncationMode(.tail)
                }
                Spacer(minLength: 8)
                if let shortcut = resolvedShortcut(for: action), !shortcut.isEmpty {
                    Text(shortcut)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(selected ? Color.white : Color.secondary)
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(selected ? Color.white.opacity(0.16)
                                           : Color.primary.opacity(0.055)))
                }
                Image(systemName: isCurrent ? "checkmark" : "return")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(selected ? Color.white.opacity(0.9) : Color.clear)
                    .frame(width: 14)
            }
            .padding(.horizontal, 9).frame(height: 48)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? Color.accentColor : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!selectable)
        .opacity(selectable ? 1 : 0.48)
        .onHover { hovering in if hovering && selectable { selectedID = action.id } }
    }

    @ViewBuilder
    private func providerIcon(_ action: ActionDef, selected: Bool) -> some View {
        if case .focusApp(let bundleID) = action.invocation,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable().scaledToFit().frame(width: 28, height: 28)
        } else {
            Image(systemName: providerSymbol(action))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(selected ? Color.white : providerColor(action))
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(selected ? Color.white.opacity(0.16)
                                   : providerColor(action).opacity(0.12)))
        }
    }

    private var emptyResults: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 22)).foregroundStyle(.tertiary)
            Text(L("没有匹配的动作")).font(.system(size: 13, weight: .medium))
            Text(L("试试动作名称、app、提供方或快捷键"))
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.top, 70)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                onPick(nil); dismiss()
            } label: {
                Label(L("清除映射"), systemImage: "trash")
                    .font(.system(size: 11.5, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(current == nil ? Color.secondary : Color.red)
            .disabled(current == nil)
            Spacer()
            Text(L("选中后绑定到 %@", target))
                .font(.system(size: 10.5)).foregroundStyle(.tertiary)
            keyHint("↑↓", L("移动"))
            keyHint("↩", L("选择"))
            keyHint("esc", L("关闭"))
        }
        .padding(.horizontal, 14).frame(height: 42)
        .background(Color.primary.opacity(scheme == .dark ? 0.035 : 0.018))
    }

    private func keyHint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.07)))
            Text(label).font(.system(size: 10.5)).foregroundStyle(.secondary)
        }
    }

    private var canonicalCurrent: String? { current.map(Actions.canonicalID) }
    private var currentAction: ActionDef? { canonicalCurrent.flatMap(Actions.action(for:)) }

    private var availableActions: [ActionDef] {
        Actions.all.filter { layer.isEmpty || $0.isAvailable(in: layer) }
    }

    private var sections: [PickerSection] {
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let matches = availableActions
                .filter { ActionPickerSearch.score($0, query: query, layer: layer) != nil }
                .sorted {
                    ActionPickerSearch.score($0, query: query, layer: layer)!
                    < ActionPickerSearch.score($1, query: query, layer: layer)!
                }
            return matches.isEmpty ? [] : [
                .init(id: "results", title: L("搜索结果"), symbol: "magnifyingglass",
                      actions: matches),
            ]
        }

        var result: [PickerSection] = []
        var used = Set<String>()
        let availableByID = Dictionary(uniqueKeysWithValues: availableActions.map { ($0.id, $0) })

        if let current = canonicalCurrent.flatMap({ availableByID[$0] }) {
            result.append(.init(id: "current", title: L("当前映射"),
                                symbol: "checkmark.circle", actions: [current]))
            used.insert(current.id)
        }

        if !layer.isEmpty {
            let suggested = availableActions.filter {
                !used.contains($0.id) && ($0.supportedApps?.contains(layer) ?? false)
            }
            if !suggested.isEmpty {
                result.append(.init(id: "suggested", title: L("推荐给 %@", AppName.of(layer)),
                                    symbol: "sparkles", actions: suggested))
                used.formUnion(suggested.map(\.id))
            }
        }

        let recents = recentIDs.compactMap { availableByID[Actions.canonicalID($0)] }
            .filter { !used.contains($0.id) }
        if !recents.isEmpty {
            result.append(.init(id: "recent", title: L("最近使用"), symbol: "clock",
                                actions: recents))
            used.formUnion(recents.map(\.id))
        }

        for group in Actions.groups {
            let actions = availableActions.filter { $0.group == group && !used.contains($0.id) }
            if !actions.isEmpty {
                result.append(.init(id: "group.\(group)", title: group,
                                    symbol: groupSymbol(group), actions: actions))
            }
        }
        return result
    }

    private var flatActions: [ActionDef] { sections.flatMap(\.actions).filter(isSelectable) }

    private func metadata(for action: ActionDef) -> String {
        let provider: String
        switch action.provider {
        case .raycast: provider = "Raycast"
        case .appProfile:
            if !layer.isEmpty, case .appShortcut(let semantic) = action.invocation {
                let customized = ConfigStore.shared.config.appProfiles[layer]?[semantic] != nil
                provider = AppName.of(layer) + "  ·  " + (customized ? L("自定义") : L("内置"))
            } else {
                provider = L("App 快捷键")
            }
        case .appFocus: provider = L("打开 app")
        case .local: provider = "JoyCoding"
        }
        guard !action.detail.isEmpty,
              action.detail != resolvedShortcut(for: action) else { return provider }
        return provider + "  ·  " + action.detail
    }

    private func resolvedShortcut(for action: ActionDef) -> String? {
        switch action.invocation {
        case .appShortcut(let semantic):
            if !layer.isEmpty, let key = AppProfiles.key(semantic, app: layer), !key.raw.isEmpty {
                return key.display
            }
            return action.detail.isEmpty ? nil : action.detail
        case .raycast:
            return action.detail == "Not assigned in Raycast" ? L("未在 Raycast 中设置")
                                                               : action.detail
        default:
            return nil
        }
    }

    private func providerSymbol(_ action: ActionDef) -> String {
        switch action.provider {
        case .raycast: return "sparkles"
        case .appProfile: return "keyboard"
        case .appFocus: return "arrow.up.forward.app.fill"
        case .local:
            if action.id.contains("scroll") { return "scroll" }
            if action.id == "ptt" { return "mic.fill" }
            return "gamecontroller.fill"
        }
    }

    private func providerColor(_ action: ActionDef) -> Color {
        switch action.provider {
        case .raycast: return .purple
        case .appProfile: return .blue
        case .appFocus: return .green
        case .local: return .orange
        }
    }

    private func groupSymbol(_ group: String) -> String? {
        switch group {
        case "Raycast": return "sparkles"
        case L("会话"): return "rectangle.stack"
        case L("浏览器"): return "globe"
        case L("切换 app"): return "arrow.left.arrow.right"
        case L("终端"): return "terminal"
        case "Claude Code": return "chevron.left.forwardslash.chevron.right"
        default: return nil
        }
    }

    private func choose(_ action: ActionDef) {
        guard isSelectable(action) else { return }
        ActionPickerRecents.record(action.id)
        onPick(action.id)
        dismiss()
    }

    private func moveSelection(_ delta: Int) {
        let actions = flatActions
        guard !actions.isEmpty else { return }
        let currentIndex = selectedID.flatMap { id in actions.firstIndex { $0.id == id } } ?? 0
        let next = min(max(currentIndex + delta, 0), actions.count - 1)
        let nextID = actions[next].id
        selectedID = nextID
        keyboardScrollID = nextID
    }

    private func isSelectable(_ action: ActionDef) -> Bool {
        !(action.provider == .raycast && action.detail == "Not assigned in Raycast")
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty
            else { return event }
            switch event.keyCode {
            case 125: moveSelection(1); return nil
            case 126: moveSelection(-1); return nil
            case 36, 76:
                if let id = selectedID, let action = flatActions.first(where: { $0.id == id }) {
                    choose(action)
                }
                return nil
            case 53: dismiss(); return nil
            default: return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}

enum ActionPickerSearch {
    static func score(_ action: ActionDef, query: String, layer: String) -> Int? {
        let tokens = normalized(query).split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return 0 }
        let name = normalized(action.name)
        let group = normalized(action.group)
        let detail = normalized(action.detail)
        let id = normalized(action.id)
        let app = normalized(layer.isEmpty ? "" : AppName.of(layer))
        let provider: String
        switch action.provider {
        case .raycast: provider = "raycast"
        case .appProfile: provider = "app shortcut keyboard"
        case .appFocus: provider = "open app switch focus"
        case .local: provider = "joycoding controller"
        }
        let shortcut: String
        if !layer.isEmpty, case .appShortcut(let semantic) = action.invocation,
           let spec = AppProfiles.key(semantic, app: layer) {
            shortcut = spec.raw + " " + spec.display
        } else {
            shortcut = ""
        }
        let aliases: [String: String] = [
            "confirm": "enter return send",
            "delete": "backspace erase",
            "clearLine": "clear erase input",
            "contextPrevious": "previous thread sidebar history up",
            "contextNext": "next thread sidebar history down",
            "ptt": "voice dictation microphone",
        ]
        let haystack = [name, group, detail, id, app, provider, shortcut,
                        aliases[action.id] ?? ""].map(normalized).joined(separator: " ")
        guard tokens.allSatisfy(haystack.contains) else { return nil }

        let joined = tokens.joined(separator: " ")
        if name == joined { return 0 }
        if name.hasPrefix(joined) { return 5 }
        if name.contains(joined) { return 10 }
        if group.contains(joined) { return 20 }
        if detail.contains(joined) { return 30 }
        return 40
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased().replacingOccurrences(of: "+", with: " ")
    }
}

private enum ActionPickerRecents {
    private static let key = "ActionPickerRecentIDs"

    static func load() -> [String] {
        (UserDefaults.standard.array(forKey: key) as? [String] ?? [])
            .map(Actions.canonicalID)
    }

    static func record(_ id: String) {
        let canonical = Actions.canonicalID(id)
        var values = load().filter { $0 != canonical }
        values.insert(canonical, at: 0)
        UserDefaults.standard.set(Array(values.prefix(5)), forKey: key)
    }
}
