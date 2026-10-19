import Foundation

/// 手机端可调节项，直接持久化，Mac 端不再参与
final class Settings: ObservableObject {
    static let shared = Settings()

    /// 鼠标左右移动灵敏度（倍率，0.1~8；滑块中心为 1.0）
    @Published var horizontalMoveSpeed: Double {
        didSet { UserDefaults.standard.set(horizontalMoveSpeed, forKey: "horizontalMoveSpeed") }
    }
    /// 鼠标上下移动灵敏度（倍率，0.1~8；滑块中心为 1.0）
    @Published var verticalMoveSpeed: Double {
        didSet { UserDefaults.standard.set(verticalMoveSpeed, forKey: "verticalMoveSpeed") }
    }
    /// 滚动灵敏度（倍率，0.2~12）
    @Published var scrollSpeed: Double {
        didSet { UserDefaults.standard.set(scrollSpeed, forKey: "scrollSpeed") }
    }
    /// 双指捏合缩放速度（倍率，0.3~3；滑块中心为 1.0）
    @Published var zoomSpeed: Double {
        didSet { UserDefaults.standard.set(zoomSpeed, forKey: "zoomSpeed") }
    }
    /// 自然滚动：两指往上滑 → 内容向上走（和 Mac 触控板一致）
    @Published var naturalScroll: Bool {
        didSet { UserDefaults.standard.set(naturalScroll, forKey: "naturalScroll") }
    }
    /// 双指点按 = 右键？（关掉则双指点按无动作）
    @Published var twoFingerRightClick: Bool {
        didSet { UserDefaults.standard.set(twoFingerRightClick, forKey: "twoFingerRightClick") }
    }
    /// 拖动：单指长按后拖
    @Published var enableDrag: Bool {
        didSet { UserDefaults.standard.set(enableDrag, forKey: "enableDrag") }
    }
    /// 手势触觉反馈：仅在识别或动作确认时触发
    @Published var hapticFeedback: Bool {
        didSet { UserDefaults.standard.set(hapticFeedback, forKey: "hapticFeedback") }
    }
    /// 系统振动脉冲倍率，用脉冲数调整体感强弱
    @Published var hapticStrength: Double {
        didSet { UserDefaults.standard.set(hapticStrength, forKey: "hapticStrength") }
    }
    /// 慢速精准移动：手指移动越慢，鼠标增益越低
    @Published var adaptiveMoveSpeed: Bool {
        didSet { UserDefaults.standard.set(adaptiveMoveSpeed, forKey: "adaptiveMoveSpeed") }
    }
    /// 慢速时鼠标移动速度相对当前横/纵向倍率的最低比例
    @Published var slowMoveMultiplier: Double {
        didSet { UserDefaults.standard.set(slowMoveMultiplier, forKey: "slowMoveMultiplier") }
    }

    private init() {
        let d = UserDefaults.standard
        let legacyMoveSpeed = d.object(forKey: "moveSpeed") as? Double ?? 1.0
        horizontalMoveSpeed = d.object(forKey: "horizontalMoveSpeed") as? Double ?? legacyMoveSpeed
        verticalMoveSpeed = d.object(forKey: "verticalMoveSpeed") as? Double ?? legacyMoveSpeed
        scrollSpeed = d.object(forKey: "scrollSpeed") as? Double ?? 1.0
        zoomSpeed = d.object(forKey: "zoomSpeed") as? Double ?? 1.0
        naturalScroll = d.object(forKey: "naturalScroll") as? Bool ?? true
        twoFingerRightClick = d.object(forKey: "twoFingerRightClick") as? Bool ?? true
        enableDrag = d.object(forKey: "enableDrag") as? Bool ?? true
        hapticFeedback = d.object(forKey: "hapticFeedback") as? Bool ?? true
        hapticStrength = d.object(forKey: "hapticStrength") as? Double ?? 0.7
        adaptiveMoveSpeed = d.object(forKey: "adaptiveMoveSpeed") as? Bool ?? true
        slowMoveMultiplier = d.object(forKey: "slowMoveMultiplier") as? Double ?? 0.35
    }
}
