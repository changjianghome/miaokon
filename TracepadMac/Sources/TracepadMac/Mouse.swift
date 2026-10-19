import Foundation
import CoreGraphics
import AppKit
import ApplicationServices
import DockSwipe

/// 鼠标注入：全部用 CGEvent，需要「辅助功能」权限。
final class Mouse {
    private(set) var cursor = CGPoint.zero
    private var lastMove = Date.distantPast
    private var lastScroll = Date.distantPast
    private var dragging = false
    private var dragMoveCount = 0

    /// 手感参数
    var moveSensitivity: Double = 2.2   // 屏幕宽度 1.0 = 整个屏幕宽度
    var scrollSensitivity: Double = 1.0

    init() {
        cursor = CGEvent(source: nil)?.location ?? .zero
    }

    private var displayBounds: CGRect {
        let screens = NSScreen.screens
        var r = screens.first?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        for s in screens.dropFirst() { r = r.union(s.frame) }
        return r
    }

    /// 统一节流：指针类 ~120Hz，滚轮 ~90Hz，避免事件洪泛把系统拖卡
    private func throttle(_ last: inout Date, hz: Double) -> Bool {
        let now = Date()
        if now.timeIntervalSince(last) < 1.0 / hz { return false }
        last = now
        return true
    }

    func move(dx: Double, dy: Double) {
        guard throttle(&lastMove, hz: 120) else { return }
        let b = displayBounds
        cursor.x += CGFloat(dx) * b.width * moveSensitivity
        cursor.y += CGFloat(dy) * b.height * moveSensitivity
        cursor.x = min(max(cursor.x, b.minX + 1), b.maxX - 1)
        cursor.y = min(max(cursor.y, b.minY + 1), b.maxY - 1)
        let type: CGEventType = dragging ? .leftMouseDragged : .mouseMoved
        if let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: cursor, mouseButton: .left) {
            e.post(tap: .cghidEventTap)
            if dragging {
                dragMoveCount += 1
                if dragMoveCount == 1 || dragMoveCount % 30 == 0 {
                    log("[mouse] leftMouseDragged posted count=\(dragMoveCount) at=\(Int(cursor.x)),\(Int(cursor.y))")
                }
            }
        } else if dragging {
            log("[mouse] failed to create leftMouseDragged event")
        }
    }

    /// 启动自检：检测是否有能力真正投递事件（无权限时 CGEvent 会静默失败）
    func selfTest() -> Bool {
        guard CGPreflightPostEventAccess() else { return false }
        // 用实际系统光标位置验证；CGEvent(source:nil)?.location 可能反映合成事件，
        // 会在投递被系统拒绝时产生假阳性。
        let before = NSEvent.mouseLocation
        let target = CGPoint(x: before.x + 1, y: before.y)
        if let e = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: target, mouseButton: .left) {
            e.post(tap: .cghidEventTap)
        }
        usleep(50_000)
        let after = NSEvent.mouseLocation
        // 挪回原位
        if let e = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: before, mouseButton: .left) {
            e.post(tap: .cghidEventTap)
        }
        return abs(after.x - target.x) < 2
    }

    func dragBegin() {
        dragging = true
        dragMoveCount = 0
        if let e = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: cursor, mouseButton: .left) {
            e.post(tap: .cghidEventTap)
            log("[mouse] leftMouseDown posted at=\(Int(cursor.x)),\(Int(cursor.y))")
        } else {
            log("[mouse] failed to create leftMouseDown event")
        }
    }

    func dragEnd() {
        guard dragging else { return }
        dragging = false
        if let e = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: cursor, mouseButton: .left) {
            e.post(tap: .cghidEventTap)
            log("[mouse] leftMouseUp posted at=\(Int(cursor.x)),\(Int(cursor.y)) dragMoves=\(dragMoveCount)")
        } else {
            log("[mouse] failed to create leftMouseUp event")
        }
        dragMoveCount = 0
    }

    func tap(button: CGMouseButton = .left, at point: CGPoint? = nil) {
        let p = point ?? cursor
        cursor = p
        let down: CGEventType = button == .right ? .rightMouseDown : .leftMouseDown
        let up: CGEventType = button == .right ? .rightMouseUp : .leftMouseUp
        // 先把指针挪到目标点，否则部分 App 会按旧位置判定
        if let m = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: button) {
            // 手势注入的鼠标点击不继承 Control 等键盘修饰键；否则 macOS 会把
            // Control+左键解释成右键。四指 Mission Control 使用带 Control 标志的键盘事件。
            m.flags = []
            m.post(tap: .cghidEventTap)
        }
        if let d = CGEvent(mouseEventSource: nil, mouseType: down, mouseCursorPosition: p, mouseButton: button) {
            d.setIntegerValueField(.mouseEventClickState, value: 1)
            d.flags = []
            d.post(tap: .cghidEventTap)
        }
        usleep(35_000)
        if let u = CGEvent(mouseEventSource: nil, mouseType: up, mouseCursorPosition: p, mouseButton: button) {
            u.setIntegerValueField(.mouseEventClickState, value: 1)
            u.flags = []
            u.post(tap: .cghidEventTap)
        }
        log("[mouse] tap injected button=\(button == .right ? "right" : "left") at=\(Int(p.x)),\(Int(p.y)) flags=0")
    }

    func doubleTap() {
        let p = cursor
        for state in 1...2 {
            if let d = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left) {
                d.setIntegerValueField(.mouseEventClickState, value: Int64(state))
                d.post(tap: .cghidEventTap)
            }
            usleep(15_000)
            if let u = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left) {
                u.setIntegerValueField(.mouseEventClickState, value: Int64(state))
                u.post(tap: .cghidEventTap)
            }
            if state == 1 { usleep(70_000) }
        }
    }

    /// dy > 0 = 内容向下滚动（手指向上滑）
    func scroll(dx: Double, dy: Double) {
        guard throttle(&lastScroll, hz: 90) else { return }
        let sx = Int32((dx * 40 * scrollSensitivity).rounded())
        let sy = Int32((dy * 40 * scrollSensitivity).rounded())
        guard sx != 0 || sy != 0 else { return }
        if let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: sy, wheel2: sx, wheel3: 0) {
            e.post(tap: .cghidEventTap)
        }
    }

    func zoom(steps: Int32) {
        guard steps != 0 else { return }
        let app = NSWorkspace.shared.frontmostApplication
        let bundleID = app?.bundleIdentifier ?? ""
        let appName = app?.localizedName ?? "unknown"

        // Video editors bind timeline zoom to modifier+scroll rather than the generic ⌘+ / ⌘−.
        if bundleID == "com.blackmagic-design.DaVinciResolve" {
            zoomWithScroll(steps: steps, modifier: .maskAlternate, appName: appName)
            return
        }
        if bundleID == "com.lemon.lvpro" || bundleID == "com.lemon.lvoverseas"
            || appName.localizedCaseInsensitiveContains("capcut")
            || bundleID.localizedCaseInsensitiveContains("jianying")
            || appName.localizedCaseInsensitiveContains("jianying")
            || appName.contains("剪映") {
            // Jianying/CapCut Mac timeline zoom: Command + vertical scroll.
            zoomWithScroll(steps: steps, modifier: .maskCommand, appName: appName)
            return
        }

        // Public CGEvent posting cannot synthesize a system-wide native magnify gesture.
        // Generic apps use ⌘+= / ⌘−; do not add Shift to the equal key for zoom-in.
        let keyCode: CGKeyCode = steps > 0 ? 0x18 : 0x1B // ANSI Equal / Minus
        let flags: CGEventFlags = .maskCommand
        for _ in 0..<abs(steps) {
            if let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true) {
                down.flags = flags
                down.post(tap: .cghidEventTap)
            }
            if let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) {
                up.flags = flags
                up.post(tap: .cghidEventTap)
            }
            usleep(25_000)
        }
        log("[mouse] zoom injected app=\(appName) mode=command-key steps=\(steps)")
    }

    private func zoomWithScroll(steps: Int32, modifier: CGEventFlags, appName: String) {
        let amount = Int32(steps.signum() * 40)
        for _ in 0..<abs(steps) {
            if let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                                   wheelCount: 2, wheel1: amount, wheel2: 0, wheel3: 0) {
                event.flags = modifier
                event.post(tap: .cghidEventTap)
            }
            usleep(20_000)
        }
        let modifierName: String
        if modifier.contains(.maskAlternate) {
            modifierName = "option"
        } else if modifier.contains(.maskCommand) {
            modifierName = "command"
        } else if modifier.contains(.maskShift) {
            modifierName = "shift"
        } else {
            modifierName = "none"
        }
        log("[mouse] zoom injected app=\(appName) mode=\(modifierName)-vertical-scroll steps=\(steps) amount=\(amount)")
    }

    func rotate() -> Bool {
        // macOS 没有通用的「旋转」输入接口，用 Cmd+[ / Cmd+] 兜底对旋转敏感的应用无意义，直接忽略
        return false
    }

    /// 三指横扫沿用 Control+方向键；四指左右在 macOS 27 走 Dock swipe/IOHID 手势事件。
    func systemSwipe(_ kind: Kind, direction: Double) {
        if kind == .fourSwipe {
            // 四指上滑触发 Mission Control；下滑仍可映射 App Exposé。
            let keyCode: CGKeyCode
            switch Int(direction) {
            case 1: keyCode = 126       // 手指上滑：Mission Control
            case -1: keyCode = 125      // 手指下滑：App Exposé
            case 2:
                if #available(macOS 27.0, *), tracepad_switch_space(true) { return }
                postSpaceKey(124)       // 旧版 macOS fallback：手指左滑切到右侧桌面
                return
            case -2:
                if #available(macOS 27.0, *), tracepad_switch_space(false) { return }
                postSpaceKey(123)       // 旧版 macOS fallback：手指右滑切到左侧桌面
                return
            default: return
            }
            postSpaceKey(keyCode)
            return
        }
        // 三指：手指向左滑 → 切到右边一个空间
        postKey(direction < 0 ? 124 : 123, flags: .maskControl)
    }

    func spaceSwipe(phase: Phase, progress: Double, velocity: Double) {
        let eventPhase: Int32
        switch phase {
        case .began: eventPhase = 1
        case .changed: eventPhase = 2
        case .ended: eventPhase = 4
        case .cancelled: eventPhase = 8
        }
        if #available(macOS 27.0, *) {
            _ = tracepad_space_swipe(eventPhase, progress, velocity)
        } else if phase == .ended, abs(progress) >= 0.25 {
            // Older macOS keeps the reliable shortcut fallback; interactive tracking is macOS 27+.
            postSpaceKey(progress < 0 ? 124 : 123)
        }
    }

    private func postKey(_ code: CGKeyCode, flags: CGEventFlags) {
        if let d = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true) {
            d.flags = flags
            d.post(tap: .cghidEventTap)
        }
        if let u = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false) {
            u.flags = flags
            u.post(tap: .cghidEventTap)
        }
    }

    /// Spaces shortcuts sent from a session event source can be ignored by Mission Control.
    /// Use the HID system source/tap and the modifier combination used by macOS Spaces switchers.
    private func postSpaceKey(_ code: CGKeyCode) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        let flags: CGEventFlags = [.maskControl, .maskSecondaryFn]
        if let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true) {
            down.flags = flags
            down.post(tap: .cghidEventTap)
        }
        if let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) {
            up.flags = flags
            up.post(tap: .cghidEventTap)
        }
    }
}
