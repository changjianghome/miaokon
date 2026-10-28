import SwiftUI

struct ContentView: View {
    @StateObject private var model = Model()
    @ObservedObject private var settings = Settings.shared
    @State private var showSettings = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color(red: 0.09, green: 0.10, blue: 0.12).ignoresSafeArea()
            TrackpadRepresentable(model: model)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                statusOverlay
                Spacer(minLength: 0)
                footer
            }
            .padding(.top, 8)
            .allowsHitTesting(false)

            VStack {
                HStack {
                    Spacer()
                    Button(action: { model.restartConnection() }) {
                        Label("重连", systemImage: "arrow.clockwise")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 11)
                            .frame(height: 38)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("重启连接")

                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 38, height: 38)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("连接设置")
                }
                Spacer()
            }
            .padding(.top, 4)
        }
        .sheet(isPresented: $showSettings) { SettingsView(model: model) }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .defersSystemGestures(on: .all)
        .preferredColorScheme(.dark)
        .onChange(of: scenePhase) { phase in
            // 回到前台时系统可能已回收 TCP 监听，主动重建，Mac 才能重新连上。
            if phase == .active { model.restartConnection() }
        }
    }

    private var statusOverlay: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(model.state.contains("已连接") ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.state).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text("USB / Wi-Fi · TCP 7311")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
            }
            Spacer()
            Text(model.hud).font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
    }

    private var footer: some View {
        Text("单指轻点=左键·滑动=移动 / 双指轻点=右键·上下左右滑=滚动·捏合=缩放 / 三指拖动=拖窗")
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
    }
}

struct TrackpadRepresentable: UIViewRepresentable {
    let model: Model

    func makeUIView(context: Context) -> TouchView {
        let v = TouchView()
        v.onSize = { model.gestures.setSize($0) }
        v.onRaw = { model.debugLog($0) }
        model.gestures.onDebug = { model.debugLog($0) }
        v.onBegan = { model.gestures.began(id: $0, at: $1) }
        v.onMovedBatch = { model.gestures.movedBatch($0) }
        v.onEnded = { model.gestures.ended(id: $0, at: $1, cancelled: $2) }
        return v
    }
    func updateUIView(_ uiView: TouchView, context: Context) {
        DispatchQueue.main.async {
            let b = uiView.window?.bounds.size ?? uiView.bounds.size
            let s = CGSize(width: max(b.width, b.height), height: min(b.width, b.height))
            model.gestures.setSize(s)
        }
    }
}

struct SettingsView: View {
    let model: Model
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        NavigationStack {
            Form {
                Section("手感") {
                    speedControl("左右移动速度", speed: settings.horizontalMoveSpeed, position: horizontalSpeedPosition)
                    speedControl("上下移动速度", speed: settings.verticalMoveSpeed, position: verticalSpeedPosition)
                    Toggle("慢速精准移动", isOn: $settings.adaptiveMoveSpeed)
                    if settings.adaptiveMoveSpeed {
                        VStack(alignment: .leading) {
                            HStack {
                                Text("慢速最低倍率")
                                Spacer()
                                Text(String(format: "%.2f×", settings.slowMoveMultiplier)).foregroundStyle(.secondary)
                            }
                            Slider(value: $settings.slowMoveMultiplier, in: 0.2...0.8, step: 0.05)
                            Text("轻慢移动时降低光标速度，快速滑动恢复到上方设置的倍率。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    VStack(alignment: .leading) {
                        HStack { Text("滚动速度"); Spacer(); Text(String(format: "%.1f×", settings.scrollSpeed)).foregroundStyle(.secondary) }
                        Slider(value: $settings.scrollSpeed, in: 0.2...12, step: 0.1)
                    }
                    speedControl("缩放速度", speed: settings.zoomSpeed, position: zoomSpeedPosition, range: 0.3...3.0)
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("滚动方向")
                            Text(settings.naturalScroll
                                 ? "自然：内容跟随双指上下、左右移动"
                                 : "反向：内容与双指上下、左右移动方向相反")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            settings.naturalScroll.toggle()
                        } label: {
                            Label(settings.naturalScroll ? "自然" : "反向", systemImage: "arrow.up.arrow.down")
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(settings.naturalScroll ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.2), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("切换滚动方向，当前\(settings.naturalScroll ? "自然" : "反向")")
                    }
                }
                Section("屏幕方向") {
                    Text("已固定为横屏。横向滑动对应光标左右移动，纵向滑动对应上下移动。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("手势开关") {
                    Toggle("双指点按 = 右键", isOn: $settings.twoFingerRightClick)
                    Toggle("单指长按拖动", isOn: $settings.enableDrag)
                    Toggle("触觉反馈（震动）", isOn: $settings.hapticFeedback)
                    Text("点击和拖拽会给短震；滚动在识别时轻震；捏合按缩放节奏轻震；四指切换在开始和完成时反馈。连续移动不会一直震动。")
                        .font(.footnote).foregroundStyle(.secondary)
                    if settings.hapticFeedback {
                        VStack(alignment: .leading) {
                            HStack {
                                Text("震动反馈力度")
                                Spacer()
                                Text(String(format: "%.1f×", settings.hapticStrength)).foregroundStyle(.secondary)
                            }
                            Slider(value: $settings.hapticStrength, in: 0.5...1.5, step: 0.1)
                            HStack {
                                Text("轻"); Spacer(); Text("标准"); Spacer(); Text("强")
                            }
                            .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    Button("测试手机震动") { model.testHaptic() }
                }
                Section("连接方式") {
                    Text("USB：连接数据线，Mac 自动通过 USB 转发连接。\nWi-Fi：手机和 Mac 接入同一局域网，在 Mac 菜单栏开启“iPhone 改用 Wi-Fi”。无需数据线。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button {
                        model.restartConnection()
                    } label: {
                        Label("重启连接", systemImage: "arrow.clockwise")
                    }
                    Text("连接没有恢复时点此重启手机端监听，Mac 会自动重新连接。Wi-Fi 连接要求两台设备在同一局域网。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("连接诊断") {
                    Button("发送连通性测试") { model.testConnection() }
                    if !model.testResult.isEmpty {
                        Text(model.testResult).font(.footnote).foregroundStyle(.secondary)
                    }
                    Text("测试需 Mac 端运行新版 miaokon-mac；成功时这里会显示 Mac 回执。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Text("请保持 miaokon-sj 横屏打开，并运行 miaokon-mac 菜单栏接收端。Wi-Fi 首次使用时，请允许本地网络访问。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("连接设置")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func speedControl(_ title: String, speed: Double, position: Binding<Double>, range: ClosedRange<Double> = 0.1...8.0) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: "%.1f×", speed)).foregroundStyle(.secondary)
            }
            Slider(value: position, in: 0...1, step: 0.01)
            HStack {
                Text(String(format: "%.1f×", range.lowerBound))
                Spacer()
                Text(String(format: "%.1f×", range.upperBound))
            }
            .overlay { Text("1.0×") }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
    }

    /// 两段对数刻度：每个方向的滑块中点都精确对应 1.0×。
    private var horizontalSpeedPosition: Binding<Double> {
        Binding(
            get: { sliderPosition(for: settings.horizontalMoveSpeed) },
            set: { settings.horizontalMoveSpeed = speed(forSliderPosition: $0) }
        )
    }

    private var verticalSpeedPosition: Binding<Double> {
        Binding(
            get: { sliderPosition(for: settings.verticalMoveSpeed) },
            set: { settings.verticalMoveSpeed = speed(forSliderPosition: $0) }
        )
    }

    private var zoomSpeedPosition: Binding<Double> {
        Binding(
            get: { zoomSliderPosition(for: settings.zoomSpeed) },
            set: { settings.zoomSpeed = zoomSpeed(forSliderPosition: $0) }
        )
    }

    /// 对数对称刻度，0.3× 到 3×，正中点固定为 1×。
    private func zoomSliderPosition(for speed: Double) -> Double {
        let value = min(max(speed, 0.3), 3.0)
        if value <= 1.0 {
            return 0.5 * log(value / 0.3) / log(1.0 / 0.3)
        }
        return 0.5 + 0.5 * log(value) / log(3.0)
    }

    private func zoomSpeed(forSliderPosition position: Double) -> Double {
        let value = min(max(position, 0.0), 1.0)
        if value <= 0.5 {
            return 0.3 * pow(1.0 / 0.3, value * 2.0)
        }
        return pow(3.0, (value - 0.5) * 2.0)
    }

    private func sliderPosition(for speed: Double) -> Double {
        let value = min(max(speed, 0.1), 8.0)
        if value <= 1.0 {
            return 0.5 * log10(value / 0.1)
        }
        return 0.5 + 0.5 * log(value) / log(8.0)
    }

    private func speed(forSliderPosition position: Double) -> Double {
        let value = min(max(position, 0.0), 1.0)
        if value <= 0.5 {
            return 0.1 * pow(10.0, value * 2.0)
        }
        return pow(8.0, (value - 0.5) * 2.0)
    }
}
