import CoreGraphics
import Foundation

/// Session-wide CGEventTap for keys, modifier changes and mouse clicks. Requires Accessibility access.
/// The tap's run loop source is attached to the main run loop, so callbacks arrive on the main thread.
@MainActor
final class KeyboardMonitor {
    /// "IBKM": marks events synthesised by IBA KeyMorph so the tap lets them through untouched.
    static let marker: Int64 = 0x4942_4B4D

    /// Return true to swallow the event. `proxy` allows posting replacement events in order.
    var handler: ((CGEventType, CGEvent, CGEventTapProxy) -> Bool)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var isRunning: Bool { tap != nil }

    /// System uptime of the last key press the tap received.
    private(set) var lastKeyDownAt: TimeInterval = 0

    /// macOS turns off taps that respond too slowly; such a tap still exists but sees nothing.
    var isEnabled: Bool {
        guard let tap = tap else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }

    func reenable() {
        if let tap = tap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    func start() -> Bool {
        if tap != nil {
            return true
        }

        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }

        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon = refcon else {
                return Unmanaged.passUnretained(event)
            }

            let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(refcon).takeUnretainedValue()
            let swallow = MainActor.assumeIsolated {
                monitor.handle(proxy: proxy, type: type, event: event)
            }
            return swallow ? nil : Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.runLoopSource = source
        // Keys pressed before the tap existed are not "missed" ones.
        lastKeyDownAt = ProcessInfo.processInfo.systemUptime
        return true
    }

    func stop() {
        if let tap = tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }

        tap = nil
        runLoopSource = nil
    }

    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // macOS disables slow taps; turn it back on.
            Log.info("Keyboard tap was disabled by macOS (\(type == .tapDisabledByTimeout ? "timeout" : "user input")); re-enabled")
            reenable()
            return false
        }

        if type == .keyDown {
            lastKeyDownAt = ProcessInfo.processInfo.systemUptime
        }

        if event.getIntegerValueField(.eventSourceUserData) == KeyboardMonitor.marker {
            return false
        }

        return handler?(type, event, proxy) ?? false
    }
}
