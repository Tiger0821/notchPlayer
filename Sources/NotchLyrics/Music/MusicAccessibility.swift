import AppKit
import ApplicationServices

/// Reads Music.app's own lyrics view through Accessibility. Apple exposes no lyrics over AppleScript and its
/// synced lyrics need private API plus account tokens, but the lyrics pane on screen is readable — each line
/// is an element, and Music marks the one it is singing.
enum MusicAccessibility {
    static func lyricsScrollArea(in app: AXUIElement) -> AXUIElement? {
        var found: AXUIElement?
        func search(_ element: AXUIElement, depth: Int) {
            guard found == nil, depth < 14 else { return }
            if string(element, kAXDescriptionAttribute) == "Lyrics",
               string(element, kAXRoleAttribute) == "AXGroup",
               let scroll = children(element).first(where: { string($0, kAXRoleAttribute) == "AXScrollArea" }) {
                found = scroll
                return
            }
            for child in children(element) { search(child, depth: depth + 1) }
        }
        // Music answers `AXWindows` with nothing at all — its window is only reachable as the main or the
        // focused one, and those come back as a single element rather than a list. Asking for the windows
        // alone, as this used to, never finds the lyrics pane on any Mac where that is true.
        for attribute in [kAXMainWindowAttribute, kAXFocusedWindowAttribute, kAXWindowsAttribute, kAXChildrenAttribute] {
            var raw: CFTypeRef?
            guard AXUIElementCopyAttributeValue(app, attribute as CFString, &raw) == .success, let raw else { continue }
            if let elements = raw as? [AXUIElement] {
                for element in elements { search(element, depth: 0) }
            } else if CFGetTypeID(raw) == AXUIElementGetTypeID() {
                search(raw as! AXUIElement, depth: 0)
            }
            if found != nil { break }
        }
        return found
    }

    /// Each line is a group holding one button; the group carries whether Music considers it current.
    static func lyricLines(in scroll: AXUIElement) -> [(text: String, selected: Bool)] {
        children(scroll).compactMap { group in
            guard let button = children(group).first,
                  let text = string(button, kAXDescriptionAttribute) ?? string(button, kAXTitleAttribute)
            else { return nil }
            return (text, string(group, kAXSelectedAttribute) == "1")
        }
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &raw) == .success,
              let kids = raw as? [AXUIElement] else { return [] }
        return kids
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success else { return nil }
        switch raw {
        case let value as String: return value
        case let value as NSNumber: return value.stringValue
        default: return nil
        }
    }
}
