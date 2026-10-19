import SwiftUI

@main
struct TracepadApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .onAppear {
                    // 让 iPhone 屏幕快速熄灭，像触控板一样——可选，这里保持常亮
                    UIApplication.shared.isIdleTimerDisabled = true
                    // 界面方向由 Info.plist 固定为横屏；保持屏幕常亮，作为 USB 触控板使用
                }
        }
    }
}
