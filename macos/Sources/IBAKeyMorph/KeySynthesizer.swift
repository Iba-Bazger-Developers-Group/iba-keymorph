import Carbon
import CoreGraphics

/// Builds synthetic keyboard events tagged with `KeyboardMonitor.marker`.
final class KeySynthesizer {
    private let source = CGEventSource(stateID: .privateState)

    func backspaces(_ count: Int) -> [CGEvent] {
        (0..<count).flatMap { _ in key(CGKeyCode(kVK_Delete), flags: []) }
    }

    /// Types text as Unicode, one character per event pair, independent of the active layout.
    func text(_ text: String) -> [CGEvent] {
        var events: [CGEvent] = []
        for character in text {
            let units = Array(String(character).utf16)
            for keyDown in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: keyDown) else {
                    continue
                }

                event.flags = []
                event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                mark(event)
                events.append(event)
            }
        }

        return events
    }

    func key(_ code: CGKeyCode, flags: CGEventFlags) -> [CGEvent] {
        [true, false].compactMap { keyDown -> CGEvent? in
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: keyDown) else {
                return nil
            }

            event.flags = flags
            mark(event)
            return event
        }
    }

    /// A copy of a swallowed key press, as a down/up pair.
    func replay(_ original: CGEvent) -> [CGEvent] {
        guard let down = original.copy(), let up = original.copy() else {
            return []
        }

        down.type = .keyDown
        up.type = .keyUp
        mark(down)
        mark(up)
        return [down, up]
    }

    /// Posts events in order: through the tap proxy when called from the tap callback (keeps them
    /// ahead of later user input), otherwise into the session event stream.
    func post(_ events: [CGEvent], proxy: CGEventTapProxy?) {
        for event in events {
            if let proxy = proxy {
                event.tapPostEvent(proxy)
            } else {
                event.post(tap: .cgSessionEventTap)
            }
        }
    }

    private func mark(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: KeyboardMonitor.marker)
    }
}
