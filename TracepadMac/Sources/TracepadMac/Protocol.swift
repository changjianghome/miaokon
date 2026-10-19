import Foundation

/// 手机 ↔ Mac 的最小协议。
///
/// 传输：TCP，一条连接上一问一答（手机写、Mac 读），字节流用 4 字节大端长度前缀分帧。
/// 帧体：UTF-8 JSON，字段见 `Event`。
///
/// 手机 → Mac 的请求：
///   hello   { "t":"hello" }
///   event   { "t":"event", "k":<kind>, "p":<phase>, "x":0..1, "y":0..1, "dx":0, "dy":0, "v":0 }
func encodeFrame(_ body: Data) -> Data {
    var len = UInt32(body.count).bigEndian
    var out = Data(bytes: &len, count: 4)
    out.append(body)
    return out
}

enum Phase: String, Codable {
    case began, changed, ended, cancelled
}

/// 手势种类（只保留触控板核心手势，不带键盘）
enum Kind: String, Codable {
    case move          // 单指平移增量（dx/dy，已归一化到屏幕比例）
    case dragBeg      // 单指长按后拖动开始
    case drag         // 拖动中
    case dragEnd
    case tap          // 单击
    case doubleTap    // 双击
    case scroll       // 双指滚动增量（dx/dy）
    case pinch        // 双指捏合，v=步进比例（>1 张开，<1 捏合）
    case rotate       // 双指旋转，v=弧度增量
    case rightClick   // 双指点按
    case threeSwipe   // 三指横扫，v = -1 向左 / +1 向右（上滑=expose，下滑=桌面）
    case fourSwipe    // 四指上滑 = 调度中心，v=1
    case spaceSwipe   // 四指左右连续滑动以拖拽切换 Spaces
    case pause        // 心跳
}

struct Event: Codable {
    var t: String
    var k: Kind?
    var p: Phase?
    var x: Double?
    var y: Double?
    var dx: Double?
    var dy: Double?
    var v: Double?
    var dbg: String?
    var id: String?
}
