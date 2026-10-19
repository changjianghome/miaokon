import UIKit
import AudioToolbox

/// 单指轻点左键、单指滑动移动；双指轻点右键、双指滑动滚动/捏合缩放；三指拖拽保持左键。
final class Gestures {

    private enum Mode: Equatable {
        case idle
        case singleCandidate
        case singleMove
        case singleFingerHolding
        case twoFingerCandidate
        case twoFingerScroll
        case twoFingerPinch
        case threeFingerLongPressCandidate
        case threeFingerHolding
        case fourFingerScrollCandidate
        case fourFingerScrolling
        case fourFingerMissionControl
        case fourFingerScreenSwitching
        case ignore
    }

    private struct T {
        var origin: CGPoint
        var last: CGPoint
        var beganAt: TimeInterval
    }

    private let tapMovementThreshold: CGFloat = 12
    private let tapDurationThreshold: TimeInterval = 0.35
    private let threeFingerLongPressDuration: TimeInterval = 0.55
    private let singleFingerLongPressDuration: TimeInterval = 0.55
    private var touches: [Int: T] = [:]
    private var viewSize: CGSize = .zero
    private var mode: Mode = .idle
    private var gestureStartedAt: TimeInterval = 0
    private var gestureID = 0
    private var maxTouchesInGesture = 0
    private var threeFingerStartedAt: TimeInterval = 0
    private var gestureCancelled = false
    private var twoFingerMovedBeyondTap = false
    private var initialPinchDistance: CGFloat = 0
    private var lastPinchDistance: CGFloat = 0
    private var pinchDistanceAccumulator: CGFloat = 0
    private let pinchStepBaseDistance: CGFloat = 30
    private var lastPinchHapticAt: TimeInterval = 0
    private let pinchHapticMinimumInterval: TimeInterval = 0.55
    private var lastMoveSampleAt: TimeInterval = 0
    private var filteredMoveVelocity: Double = 0
    private let fourFingerSpaceSwipeStartThreshold = 20.0
    private let fourFingerSpaceSwipeProgressScale = 3.0
    private var fourFingerSpaceSwipeProgress = 0.0
    private var fourFingerSpaceSwipeLastDelta = 0.0

    var send: ((Ev) -> Void)?
    var onHUD: ((String, Int) -> Void)?
    var onDebug: ((String) -> Void)?
    var horizontalMoveSpeed: Double = 1.0
    var verticalMoveSpeed: Double = 1.0
    var adaptiveMoveSpeedEnabled = true
    var slowMoveMultiplier = 0.35
    var scrollSpeed: Double = 1.0
    var zoomSpeed: Double = 1.0
    var hapticFeedbackEnabled = true
    var hapticStrength = 0.7
    var naturalScroll = true
    var twoFingerRightClick = true
    var singleFingerDragEnabled = true

    func setSize(_ s: CGSize) {
        guard s.width > 1, s.height > 1 else { return }
        if s != viewSize {
            viewSize = s
            onDebug?("size \(Int(s.width))x\(Int(s.height))")
        }
    }

    func began(id: Int, at p: CGPoint) {
        let previousMode = mode
        if touches.isEmpty {
            gestureID += 1
            mode = .singleCandidate
            gestureStartedAt = ProcessInfo.processInfo.systemUptime
            gestureCancelled = false
            twoFingerMovedBeyondTap = false
            maxTouchesInGesture = 0
            fourFingerSpaceSwipeProgress = 0
            fourFingerSpaceSwipeLastDelta = 0
            lastMoveSampleAt = 0
            filteredMoveVelocity = 0
        } else if touches.count == 1 {
            if mode == .singleCandidate {
                mode = .twoFingerCandidate
            } else if mode == .singleMove {
                mode = .twoFingerScroll
            } else {
                mode = .ignore
            }
        } else if touches.count == 2, mode == .twoFingerCandidate {
            mode = .threeFingerLongPressCandidate
            threeFingerStartedAt = ProcessInfo.processInfo.systemUptime
        } else if touches.count == 3, mode == .threeFingerLongPressCandidate {
            mode = .fourFingerScrollCandidate
        } else {
            mode = .ignore
        }
        let now = ProcessInfo.processInfo.systemUptime
        touches[id] = T(origin: p, last: p, beganAt: now)
        maxTouchesInGesture = max(maxTouchesInGesture, touches.count)
        onDebug?("gesture=\(gestureID) touch+ id=\(id) count=\(touches.count) mode=\(modeName(mode)) from=\(modeName(previousMode)) point=\(Int(p.x)),\(Int(p.y))")
        if touches.count == 2, mode == .twoFingerCandidate {
            initialPinchDistance = distanceBetweenTouches()
            lastPinchDistance = initialPinchDistance
            pinchDistanceAccumulator = 0
        }
        onHUD?(hudLabel, touches.count)
    }

    func moved(id: Int, to p: CGPoint) {
        movedBatch([(id: id, point: p)])
    }

    func movedBatch(_ updates: [(id: Int, point: CGPoint)]) {
        var deltas: [CGPoint] = []
        for update in updates {
            guard var t = touches[update.id] else { continue }
            let d = CGPoint(x: update.point.x - t.last.x, y: update.point.y - t.last.y)
            t.last = update.point
            touches[update.id] = t
            deltas.append(d)
        }
        guard !deltas.isEmpty else { return }
        if mode == .singleCandidate, touches.count == 1, singleFingerDragEnabled,
           ProcessInfo.processInfo.systemUptime - gestureStartedAt >= singleFingerLongPressDuration {
            beginSingleFingerDrag()
        }
        if mode == .singleCandidate,
           touches.count == 1,
           touches.values.contains(where: { hypot($0.last.x - $0.origin.x, $0.last.y - $0.origin.y) > tapMovementThreshold }) {
            mode = .singleMove
            onDebug?("gesture=\(gestureID) classify=singleMove reason=travel_gt_\(Int(tapMovementThreshold))pt")
            onHUD?(hudLabel, touches.count)
        } else if mode == .twoFingerCandidate, touches.count == 2 {
            let points = Array(touches.values)
            let originCenter = CGPoint(x: (points[0].origin.x + points[1].origin.x) / 2,
                                       y: (points[0].origin.y + points[1].origin.y) / 2)
            let currentCenter = CGPoint(x: (points[0].last.x + points[1].last.x) / 2,
                                        y: (points[0].last.y + points[1].last.y) / 2)
            let centerDX = currentCenter.x - originCenter.x
            let centerDY = currentCenter.y - originCenter.y
            let centerTravel = hypot(centerDX, centerDY)
            let distanceDelta = distanceBetweenTouches() - initialPinchDistance
            let maxFingerTravel = points.map { hypot($0.last.x - $0.origin.x, $0.last.y - $0.origin.y) }.max() ?? 0
            let baselineLength = max(initialPinchDistance, 1)
            let baselineX = (points[1].origin.x - points[0].origin.x) / baselineLength
            let baselineY = (points[1].origin.y - points[0].origin.y) / baselineLength
            let firstDX = points[0].last.x - points[0].origin.x
            let firstDY = points[0].last.y - points[0].origin.y
            let secondDX = points[1].last.x - points[1].origin.x
            let secondDY = points[1].last.y - points[1].origin.y
            let firstOutward = -(firstDX * baselineX + firstDY * baselineY)
            let secondOutward = secondDX * baselineX + secondDY * baselineY
            let bothExpand = firstOutward > 4 && secondOutward > 4
            let bothContract = firstOutward < -4 && secondOutward < -4

            if abs(distanceDelta) >= 20, bothExpand || bothContract {
                mode = .twoFingerPinch
                lastPinchDistance = distanceBetweenTouches()
                pinchDistanceAccumulator = 0
                lastPinchHapticAt = ProcessInfo.processInfo.systemUptime
                haptic(.medium)
                emitPinchDistance(distanceDelta)
                onHUD?(hudLabel, touches.count)
            } else if centerTravel >= 12, abs(distanceDelta) <= max(16, centerTravel * 1.8) {
                mode = .twoFingerScroll
                haptic(.medium)
                onHUD?(hudLabel, touches.count)
            } else if maxFingerTravel > tapMovementThreshold {
                twoFingerMovedBeyondTap = true
            }
        } else if mode == .fourFingerScrollCandidate, touches.count == 4 {
            let points = Array(touches.values)
            let dx = points.reduce(0.0) { $0 + Double($1.last.x - $1.origin.x) } / 4.0
            let dy = points.reduce(0.0) { $0 + Double($1.last.y - $1.origin.y) } / 4.0
            let movedFingers = points.filter {
                hypot($0.last.x - $0.origin.x, $0.last.y - $0.origin.y) > 6
            }.count
            let movedSpaceFingers = points.filter {
                hypot($0.last.x - $0.origin.x, $0.last.y - $0.origin.y) > 12
            }.count
            if abs(dx) > abs(dy), movedSpaceFingers >= 3, abs(dx) >= fourFingerSpaceSwipeStartThreshold {
                mode = .fourFingerScreenSwitching
                fourFingerSpaceSwipeProgress = currentFourFingerSpaceSwipeProgress()
                fourFingerSpaceSwipeLastDelta = 0
                haptic(.medium)
                send?(Ev(k: .spaceSwipe, dx: fourFingerSpaceSwipeProgress, p: .began,
                         dbg: "four-finger space swipe began progress=\(String(format: "%.3f", fourFingerSpaceSwipeProgress))"))
                onDebug?("four-finger space swipe began")
                onHUD?(hudLabel, touches.count)
                return
            } else if abs(dy) >= abs(dx), movedFingers >= 3, abs(dy) >= 12 {
                if dy < 0 {
                    guard abs(dy) >= 28 else { return }
                    mode = .fourFingerMissionControl
                    haptic(.heavy)
                    send?(Ev(k: .fourSwipe, v: 1, dbg: "four-finger up: Mission Control"))
                    onDebug?("four-finger up: Mission Control")
                    onHUD?(hudLabel, touches.count)
                    return
                }
                mode = .fourFingerScrolling
                haptic(.medium)
                sendFourFingerScroll(dx: 0, dy: dy, debug: "four-finger screen scroll")
                onDebug?("four-finger screen scroll")
                onHUD?(hudLabel, touches.count)
                return
            }
        } else if mode == .threeFingerLongPressCandidate,
                  touches.values.contains(where: { hypot($0.last.x - $0.origin.x, $0.last.y - $0.origin.y) > tapMovementThreshold }) {
            // 三指移动直接启动左键拖拽；静止达到阈值则由 tick() 启动长按。
            mode = .threeFingerHolding
            haptic(.heavy)
            send?(Ev(k: .dragBeg, dbg: "gesture=\(gestureID) three-finger move drag began"))
            let dx = touches.values.reduce(0.0) { $0 + Double($1.last.x - $1.origin.x) } / 3.0
            let dy = touches.values.reduce(0.0) { $0 + Double($1.last.y - $1.origin.y) } / 3.0
            sendDrag(dx: dx, dy: dy)
            onDebug?("three-finger drag began")
            onHUD?(hudLabel, touches.count)
            return
        }
        guard deltas.contains(where: { hypot($0.x, $0.y) > 0.1 }) else { return }

        switch mode {
        case .singleCandidate, .twoFingerCandidate, .threeFingerLongPressCandidate:
            return
        case .singleMove:
            guard touches.count == 1, viewSize.width > 1 else { return }
            let dx = deltas.reduce(0.0) { $0 + Double($1.x) }
            let dy = deltas.reduce(0.0) { $0 + Double($1.y) }
            sendMove(dx: dx, dy: dy)
        case .singleFingerHolding:
            guard touches.count == 1 else { return }
            let dx = deltas.reduce(0.0) { $0 + Double($1.x) }
            let dy = deltas.reduce(0.0) { $0 + Double($1.y) }
            sendDrag(dx: dx, dy: dy)
        case .twoFingerScroll:
            guard touches.count == 2 else { return }
            let direction = naturalScroll ? 1.0 : -1.0
            let divisor = 40.0 * Double(touches.count)
            let dx = deltas.reduce(0.0) { $0 + Double($1.x) } * scrollSpeed * direction / divisor
            let dy = deltas.reduce(0.0) { $0 + Double($1.y) } * scrollSpeed * direction / divisor
            guard dx.isFinite, dy.isFinite, abs(dx) > 0.0001 || abs(dy) > 0.0001 else { return }
            send?(Ev(k: .scroll, dx: dx, dy: dy))
        case .twoFingerPinch:
            guard touches.count == 2 else { return }
            let distance = distanceBetweenTouches()
            emitPinchDistance(distance - lastPinchDistance)
            lastPinchDistance = distance
        case .threeFingerHolding:
            guard touches.count == 3 else { return }
            let dx = deltas.reduce(0.0) { $0 + Double($1.x) } / 3.0
            let dy = deltas.reduce(0.0) { $0 + Double($1.y) } / 3.0
            sendDrag(dx: dx, dy: dy)
        case .fourFingerScrollCandidate:
            return
        case .fourFingerScrolling:
            sendFourFingerScroll(dx: 0, dy: deltas.reduce(0.0) { $0 + Double($1.y) } / 4.0)
        case .fourFingerMissionControl:
            return
        case .fourFingerScreenSwitching:
            guard touches.count == 4 else { return }
            let progress = currentFourFingerSpaceSwipeProgress()
            let delta = progress - fourFingerSpaceSwipeProgress
            guard delta.isFinite, abs(delta) > 0.00001 else { return }
            fourFingerSpaceSwipeProgress = progress
            fourFingerSpaceSwipeLastDelta = delta
            send?(Ev(k: .spaceSwipe, dx: progress, p: .changed))
        case .idle, .ignore:
            return
        }
    }

    private func sendMove(dx: Double, dy: Double) {
        guard viewSize.width > 1 else { return }
        // app 固定横屏：横向滑动按触控板短边归一化，纵向滑动按长边归一化。
        let nx = dx / Double(viewSize.height)
        let ny = dy / Double(viewSize.width)
        guard nx.isFinite, ny.isFinite else { return }
        let gain = adaptiveMoveSpeedEnabled ? adaptiveMoveGain(dx: dx, dy: dy) : 1.0
        send?(Ev(k: .move, dx: nx * horizontalMoveSpeed * gain, dy: ny * verticalMoveSpeed * gain))
    }

    /// 慢速移动使用较低增益，快速移动平滑回到用户设定的基础倍率。
    private func adaptiveMoveGain(dx: Double, dy: Double) -> Double {
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = lastMoveSampleAt > 0 ? now - lastMoveSampleAt : now - gestureStartedAt
        let sampleDuration = min(max(elapsed, 1.0 / 240.0), 0.25)
        let instantaneousVelocity = hypot(dx, dy) / sampleDuration
        if lastMoveSampleAt == 0 || elapsed > 0.25 {
            filteredMoveVelocity = instantaneousVelocity
        } else {
            let smoothing = 1.0 - exp(-sampleDuration / 0.075)
            filteredMoveVelocity += (instantaneousVelocity - filteredMoveVelocity) * smoothing
        }
        lastMoveSampleAt = now

        let lowSpeed = 70.0
        let fullSpeed = 520.0
        let progress = min(max((filteredMoveVelocity - lowSpeed) / (fullSpeed - lowSpeed), 0.0), 1.0)
        let easedProgress = progress * progress * (3.0 - 2.0 * progress)
        let floor = min(max(slowMoveMultiplier, 0.2), 0.8)
        return floor + (1.0 - floor) * easedProgress
    }

    private func sendDrag(dx: Double, dy: Double) {
        guard viewSize.width > 1 else { return }
        let nx = dx / Double(viewSize.height)
        let ny = dy / Double(viewSize.width)
        guard nx.isFinite, ny.isFinite else { return }
        guard abs(nx) > 0.000001 || abs(ny) > 0.000001 else { return }
        send?(Ev(k: .drag, dx: nx * horizontalMoveSpeed, dy: ny * verticalMoveSpeed))
    }

    private func sendFourFingerScroll(dx: Double, dy: Double, debug: String? = nil) {
        let direction = naturalScroll ? 1.0 : -1.0
        let scrollDX = dx * scrollSpeed / 40.0
        let scrollDY = dy * scrollSpeed * direction / 40.0
        guard scrollDX.isFinite, scrollDY.isFinite,
              abs(scrollDX) > 0.0001 || abs(scrollDY) > 0.0001 else { return }
        send?(Ev(k: .scroll, dx: scrollDX, dy: scrollDY, dbg: debug))
    }

    private func distanceBetweenTouches() -> CGFloat {
        let points = Array(touches.values)
        guard points.count == 2 else { return 0 }
        return hypot(points[1].last.x - points[0].last.x, points[1].last.y - points[0].last.y)
    }

    private func currentFourFingerSpaceSwipeProgress() -> Double {
        guard touches.count == 4, viewSize.width > 1 else { return fourFingerSpaceSwipeProgress }
        let points = Array(touches.values)
        let dx = points.reduce(0.0) { $0 + Double($1.last.x - $1.origin.x) } / 4.0
        return min(max(dx / Double(viewSize.width) * fourFingerSpaceSwipeProgressScale, -3.0), 3.0)
    }

    private func finishFourFingerSpaceSwipe(cancelled: Bool) {
        guard mode == .fourFingerScreenSwitching else { return }
        if !cancelled { haptic(.heavy) }
        send?(Ev(k: .spaceSwipe, dx: fourFingerSpaceSwipeProgress,
                 v: cancelled ? 0 : fourFingerSpaceSwipeLastDelta * 100,
                 p: cancelled ? .cancelled : .ended,
                 dbg: "four-finger space swipe \(cancelled ? "cancelled" : "ended") progress=\(String(format: "%.3f", fourFingerSpaceSwipeProgress))"))
        onDebug?("four-finger space swipe \(cancelled ? "cancelled" : "ended")")
        mode = .ignore
    }

    private func emitPinchDistance(_ delta: CGFloat) {
        pinchDistanceAccumulator += delta
        let speed = min(max(zoomSpeed, 0.3), 3.0)
        let stepDistance = pinchStepBaseDistance / CGFloat(speed)
        var emittedZoomStep = false
        while pinchDistanceAccumulator >= stepDistance {
            send?(Ev(k: .pinch, v: 1))
            emittedZoomStep = true
            pinchDistanceAccumulator -= stepDistance
        }
        while pinchDistanceAccumulator <= -stepDistance {
            send?(Ev(k: .pinch, v: -1))
            emittedZoomStep = true
            pinchDistanceAccumulator += stepDistance
        }
        let now = ProcessInfo.processInfo.systemUptime
        if emittedZoomStep, now - lastPinchHapticAt >= pinchHapticMinimumInterval {
            lastPinchHapticAt = now
            haptic(.light)
        }
    }

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle, force: Bool = false) {
        guard force || hapticFeedbackEnabled else { return }
        let basePulseCount: Int
        switch style {
        case .light, .soft:
            basePulseCount = 1
        case .medium, .rigid:
            basePulseCount = 2
        case .heavy:
            basePulseCount = 3
        @unknown default:
            basePulseCount = 1
        }
        let strength = min(max(hapticStrength, 0.5), 1.5)
        let pulseCount = min(max(Int((Double(basePulseCount) * strength).rounded()), 1), 4)
        let play = {
            for pulse in 0..<pulseCount {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(pulse) * 0.18) {
                    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                }
            }
        }
        if Thread.isMainThread { play() }
        else { DispatchQueue.main.async(execute: play) }
    }

    func testHaptic() {
        // 独立测试与手势使用同一系统振动接口，并绕过触觉开关。
        haptic(.heavy, force: true)
    }

    func ended(id: Int, at p: CGPoint, cancelled: Bool = false) {
        if cancelled { gestureCancelled = true }
        if var touch = touches[id] {
            touch.last = p
            touches[id] = touch
        }
        let endedMode = mode
        let activeAtEnd = touches[id]
        let elapsed = activeAtEnd.map { ProcessInfo.processInfo.systemUptime - $0.beganAt } ?? 0
        let travel = activeAtEnd.map { hypot($0.last.x - $0.origin.x, $0.last.y - $0.origin.y) } ?? 0
        let origin = activeAtEnd?.origin ?? .zero
        let last = activeAtEnd?.last ?? .zero
        onDebug?("gesture=\(gestureID) touch- id=\(id) remaining=\(max(0, touches.count - 1)) mode=\(modeName(endedMode)) cancelled=\(cancelled) touchDuration=\(String(format: "%.3f", elapsed)) travel=\(Int(travel))pt from=\(Int(origin.x)),\(Int(origin.y)) to=\(Int(last.x)),\(Int(last.y))")
        if mode == .fourFingerScreenSwitching {
            finishFourFingerSpaceSwipe(cancelled: cancelled)
        }
        let wasHoldingLeftButton = mode == .threeFingerHolding || mode == .singleFingerHolding
        touches.removeValue(forKey: id)
        if wasHoldingLeftButton {
            haptic(.medium)
            send?(Ev(k: .dragEnd, dbg: "gesture=\(gestureID) drag released mode=\(modeName(endedMode)) cancelled=\(cancelled)"))
            onDebug?("gesture=\(gestureID) drag released mode=\(modeName(endedMode)) cancelled=\(cancelled)")
            mode = touches.isEmpty ? .idle : .ignore
        }
        if touches.isEmpty {
            let duration = ProcessInfo.processInfo.systemUptime - gestureStartedAt
            if !wasHoldingLeftButton, !gestureCancelled, duration <= tapDurationThreshold {
                switch mode {
                case .singleCandidate:
                    haptic(.medium)
                    send?(Ev(k: .tap, dbg: "gesture=\(gestureID) single tap"))
                    onDebug?("gesture=\(gestureID) result=leftClick fingers=1 duration=\(String(format: "%.3f", duration))")
                case .twoFingerCandidate where twoFingerRightClick && !twoFingerMovedBeyondTap:
                    haptic(.heavy)
                    send?(Ev(k: .rightClick, dbg: "gesture=\(gestureID) two-finger tap"))
                    onDebug?("gesture=\(gestureID) result=rightClick peakTouches=\(maxTouchesInGesture) duration=\(String(format: "%.3f", duration))")
                default:
                    onDebug?("gesture=\(gestureID) result=noClick mode=\(modeName(mode)) duration=\(String(format: "%.3f", duration)) cancelled=\(gestureCancelled)")
                }
            }
            mode = .idle
            onHUD?("就绪", 0)
        } else {
            onHUD?(hudLabel, touches.count)
        }
    }

    private var hudLabel: String {
        switch mode {
        case .singleCandidate: return "单击/移动"
        case .singleMove: return "移动"
        case .singleFingerHolding: return "单指拖拽"
        case .twoFingerCandidate: return "双指点按/滚动"
        case .twoFingerScroll: return "滚动"
        case .twoFingerPinch: return "缩放"
        case .threeFingerLongPressCandidate: return "三指长按"
        case .threeFingerHolding: return "左键按住"
        case .fourFingerScrollCandidate: return "四指滑屏"
        case .fourFingerScrolling: return "屏幕滚动"
        case .fourFingerMissionControl: return "调度中心"
        case .fourFingerScreenSwitching: return "切换桌面"
        case .idle: return "就绪"
        case .ignore: return "多指忽略"
        }
    }

    /// 三指保持静止到达阈值后发送左键按下；释放在 touchesEnded/touchesCancelled 中处理。
    func tick() {
        if mode == .singleCandidate, singleFingerDragEnabled, touches.count == 1,
           ProcessInfo.processInfo.systemUptime - gestureStartedAt >= singleFingerLongPressDuration {
            beginSingleFingerDrag()
            return
        }
        guard mode == .threeFingerLongPressCandidate,
              touches.count == 3,
              ProcessInfo.processInfo.systemUptime - threeFingerStartedAt >= threeFingerLongPressDuration else { return }
        mode = .threeFingerHolding
        haptic(.heavy)
        send?(Ev(k: .dragBeg, dbg: "gesture=\(gestureID) three-finger hold began"))
        onDebug?("gesture=\(gestureID) three-finger hold began duration=\(String(format: "%.3f", ProcessInfo.processInfo.systemUptime - threeFingerStartedAt))")
        onHUD?(hudLabel, touches.count)
    }

    private func beginSingleFingerDrag() {
        guard mode == .singleCandidate, touches.count == 1 else { return }
        mode = .singleFingerHolding
        haptic(.heavy)
        send?(Ev(k: .dragBeg, dbg: "gesture=\(gestureID) single-finger long-press drag began"))
        onDebug?("gesture=\(gestureID) single-finger drag began threshold=\(singleFingerLongPressDuration)s")
        onHUD?(hudLabel, touches.count)
    }

    private func modeName(_ mode: Mode) -> String {
        switch mode {
        case .idle: return "idle"
        case .singleCandidate: return "singleCandidate"
        case .singleMove: return "singleMove"
        case .singleFingerHolding: return "singleFingerHolding"
        case .twoFingerCandidate: return "twoFingerCandidate"
        case .twoFingerScroll: return "twoFingerScroll"
        case .twoFingerPinch: return "twoFingerPinch"
        case .threeFingerLongPressCandidate: return "threeFingerCandidate"
        case .threeFingerHolding: return "threeFingerHolding"
        case .fourFingerScrollCandidate: return "fourFingerCandidate"
        case .fourFingerScrolling: return "fourFingerScrolling"
        case .fourFingerMissionControl: return "fourFingerMissionControl"
        case .fourFingerScreenSwitching: return "fourFingerScreenSwitching"
        case .ignore: return "ignore"
        }
    }
}
