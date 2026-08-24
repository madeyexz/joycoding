import Foundation
import CoreGraphics

struct RaycastShortcut: Equatable {
    let modifiers: [String]
    let keyCode: CGKeyCode

    var display: String {
        let modifierNames = modifiers.map {
            switch $0 {
            case "cmd": return "⌘"
            case "shift": return "⇧"
            case "rightshift": return "R⇧"
            case "alt": return "⌥"
            case "rightalt": return "R⌥"
            case "ctrl": return "⌃"
            case "rightctrl": return "R⌃"
            case "fn": return "fn"
            default: return $0
            }
        }.joined()
        return modifierNames + RaycastShortcuts.keyName(keyCode)
    }
}

/// Read-only bridge to Raycast's cloud-sync settings snapshot.
///
/// Raycast's live *.db files are encrypted/custom data. Its local cloud-sync
/// snapshot is JSON and contains the exact global hotkey definitions, including
/// sided modifiers such as Right Shift. JoyCoding never writes either source.
enum RaycastShortcuts {
    private struct Definition {
        let actionID: String
        let name: String
        let commandID: String?
    }

    private static let definitions = [
        Definition(actionID: "raycastLauncher", name: "Open Raycast", commandID: nil),
        Definition(actionID: "raycastDictation", name: "Raycast Dictation",
                   commandID: "c:r:dictation::-::dictateText"),
        Definition(actionID: "raycastAIChat", name: "Raycast AI Chat",
                   commandID: "c:r:ai::-::openAiChat"),
        Definition(actionID: "raycastClipboardHistory", name: "Raycast Clipboard History",
                   commandID: "c:r:clipboard-history::-::history"),
        Definition(actionID: "raycastPasteSequential", name: "Raycast Paste Sequentially",
                   commandID: "c:r:clipboard-history::-::pasteSequential"),
        Definition(actionID: "raycastEmojiPicker", name: "Raycast Emoji Picker",
                   commandID: "c:r:emoji-picker::-::searchEmoji"),
        Definition(actionID: "raycastNotes", name: "Raycast Notes",
                   commandID: "c:r:notes::-::open"),
        Definition(actionID: "raycastArc", name: "Raycast · Arc",
                   commandID: "c:r:applications::*::application::=::/Applications/Arc.app"),
        Definition(actionID: "raycastWeChat", name: "Raycast · WeChat",
                   commandID: "c:r:applications::*::application::=::/Applications/WeChat.app"),
        Definition(actionID: "raycastSlack", name: "Raycast · Slack",
                   commandID: "c:r:applications::*::application::=::/Applications/Slack.app"),
        Definition(actionID: "raycastCodex", name: "Raycast · Codex",
                   commandID: "c:r:applications::*::application::=::/Applications/ChatGPT.app"),
        Definition(actionID: "raycastHeptabase", name: "Raycast · Heptabase",
                   commandID: "c:r:applications::*::application::=::/Applications/Heptabase.app"),
        Definition(actionID: "raycastAmp", name: "Raycast · Amp",
                   commandID: "c:r:applications::*::application::=::/Applications/Amp.app"),
        Definition(actionID: "raycastWarp", name: "Raycast · Warp",
                   commandID: "c:r:applications::*::application::=::/Applications/Warp.app"),
        Definition(actionID: "raycastFinder", name: "Raycast · Finder",
                   commandID: "c:r:applications::*::application::=::/System/Library/CoreServices/Finder.app"),
        Definition(actionID: "raycastPreviousSpace", name: "Raycast · Previous Space",
                   commandID: "c:r:window-management::-::switchToPreviousSpace"),
        Definition(actionID: "raycastNextSpace", name: "Raycast · Next Space",
                   commandID: "c:r:window-management::-::switchToNextSpace"),
    ]

    private static let actionToCommand = Dictionary(uniqueKeysWithValues:
        definitions.compactMap { d in d.commandID.map { (d.actionID, $0) } })

    private static var cachedURL: URL?
    private static var cachedDate: Date?
    private static var cached: [String: RaycastShortcut] = [:]

    static var actionDefinitions: [ActionDef] {
        definitions.filter { $0.actionID != "raycastDictation" }.map { definition in
            let detail = shortcut(for: definition.actionID)?.display ?? "Not assigned in Raycast"
            return ActionDef(definition.actionID, definition.name, detail, group: "Raycast",
                             invocation: .raycast(definition.actionID))
        }
    }

    static func shortcut(for actionID: String) -> RaycastShortcut? {
        reloadIfNeeded()
        return cached[actionID]
    }

    static func trigger(_ actionID: String) {
        guard let shortcut = shortcut(for: actionID) else {
            NSLog("[JoyCoding] Raycast shortcut is not assigned: \(actionID)")
            return
        }
        KeySynth.shortcutStroke(shortcut.modifiers, keyCode: shortcut.keyCode)
    }

    /// Internal for tests and for keeping JSON interpretation independent from IO.
    static func parseSnapshot(_ data: Data) -> [String: RaycastShortcut] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tables = root["tables"] as? [String: Any]
        else { return [:] }

        var result: [String: RaycastShortcut] = [:]
        if let general = (tables["general_settings"] as? [[String: Any]])?.first,
           let hotkey = parseHotkey(general["globalHotkey"]) {
            result["raycastLauncher"] = hotkey
        }

        guard let commands = tables["commands"] as? [[String: Any]] else { return result }
        let commandToAction = Dictionary(uniqueKeysWithValues:
            actionToCommand.map { ($0.value, $0.key) })
        for command in commands {
            guard (command["enabled"] as? Bool) != false,
                  let id = command["id"] as? String,
                  let actionID = commandToAction[id],
                  let hotkey = parseHotkey(command["macosHotkey"])
            else { continue }
            result[actionID] = hotkey
        }
        return result
    }

    private static func reloadIfNeeded() {
        guard let url = newestSnapshotURL() else { return }
        let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate
        guard url != cachedURL || date != cachedDate else { return }
        cachedURL = url
        cachedDate = date
        guard let data = try? Data(contentsOf: url) else { cached = [:]; return }
        cached = parseSnapshot(data)
    }

    private static func newestSnapshotURL() -> URL? {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.raycast.macos")
            .appendingPathComponent("cloud-sync/settings-snapshots", isDirectory: true)
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles])) ?? []
        return urls.filter { $0.pathExtension.lowercased() == "json" }
            .max { lhs, rhs in lhs.lastPathComponent < rhs.lastPathComponent }
    }

    private static func parseHotkey(_ value: Any?) -> RaycastShortcut? {
        guard let hotkey = value as? [String: Any],
              let kind = hotkey["kind"] as? [String: Any],
              kind["type"] as? String == "SingleStep",
              let shortcut = kind["shortcut"] as? [String: Any],
              let key = shortcut["key"] as? [String: Any],
              let keyCode = parseKeyCode(key)
        else { return nil }

        let modifiers = (shortcut["modifiers"] as? [[String: Any]] ?? []).compactMap {
            modifierName($0)
        }
        return RaycastShortcut(modifiers: modifiers,
                               keyCode: keyCode)
    }

    private static func parseKeyCode(_ key: [String: Any]) -> CGKeyCode? {
        if let number = key["code"] as? NSNumber {
            return CGKeyCode(number.uint16Value)
        }
        guard key["type"] as? String == "LayoutDependent",
              let keyType = key["keyType"] as? [String: Any],
              keyType["type"] as? String == "Control",
              let name = keyType["key"] as? String
        else { return nil }
        return [
            "ArrowLeft": CGKeyCode(123), "ArrowRight": CGKeyCode(124),
            "ArrowDown": CGKeyCode(125), "ArrowUp": CGKeyCode(126),
        ][name]
    }

    private static func modifierName(_ value: [String: Any]) -> String? {
        guard let modifier = value["modifier"] as? String else { return nil }
        let base: String
        switch modifier {
        case "Meta": base = "cmd"
        case "Shift": base = "shift"
        case "Alt": base = "alt"
        case "Ctrl": base = "ctrl"
        case "Fn": base = "fn"
        default: return nil
        }
        guard value["directionality"] as? String == "right" else { return base }
        switch base {
        case "shift": return "rightshift"
        case "alt": return "rightalt"
        case "ctrl": return "rightctrl"
        default: return base
        }
    }

    static func keyName(_ code: CGKeyCode) -> String {
        switch code {
        case 36: return "↩"
        case 48: return "⇥"
        case 49: return "Space"
        case 51: return "⌫"
        case 53: return "Esc"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default:
            let names: [CGKeyCode: String] = [
                0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z",
                7: "X", 8: "C", 9: "V", 11: "B", 12: "Q", 13: "W",
                14: "E", 15: "R", 16: "Y", 17: "T", 31: "O", 32: "U",
                34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N",
                46: "M",
            ]
            return names[code] ?? "Key \(code)"
        }
    }
}
