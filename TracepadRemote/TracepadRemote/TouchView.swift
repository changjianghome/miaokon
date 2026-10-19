import UIKit

/// 触摸采集层：多指、无延迟，不抢任何系统手势。
final class TouchView: UIView {
    var onBegan: ((Int, CGPoint) -> Void)?
    var onMoved: ((Int, CGPoint) -> Void)?
    var onMovedBatch: (([(id: Int, point: CGPoint)]) -> Void)?
    var onEnded: ((Int, CGPoint, Bool) -> Void)?
    var onSize: ((CGSize) -> Void)?
    var onRaw: ((String) -> Void)?

    init() {
        super.init(frame: .zero)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
    }
    required init?(coder: NSCoder) { fatalError() }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // 视图挂到窗口后才会有真实尺寸，这里主动上报一次，避免开始滑动时 size 还是 0
        onSize?(window?.bounds.size ?? bounds.size)
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        onSize?(window?.bounds.size ?? bounds.size)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        onRaw?("began \(touches.count) total=\(event?.allTouches?.count ?? 0)")
        for t in touches { onBegan?(t.hashValue, t.location(in: self)) }
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        let updates = touches.map { (id: $0.hashValue, point: $0.location(in: self)) }
        if let onMovedBatch {
            onMovedBatch(updates)
        } else {
            for update in updates { onMoved?(update.id, update.point) }
        }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        onRaw?("ended remaining=\(event?.allTouches?.count ?? 0)")
        for t in touches { onEnded?(t.hashValue, t.location(in: self), false) }
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        onRaw?("cancelled (系统手势抢走了)")
        for t in touches { onEnded?(t.hashValue, t.location(in: self), true) }
    }
}
