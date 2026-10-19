import Foundation

enum Kind: String {
    case move, dragBeg, drag, dragEnd, tap, doubleTap
    case scroll, pinch, rotate, rightClick
    case threeSwipe, fourSwipe, spaceSwipe, pause
}

enum Phase: String {
    case began, changed, ended, cancelled
}

struct Ev {
    var k: Kind
    var dx: Double = 0
    var dy: Double = 0
    var v: Double = 0
    var p: Phase? = nil
    var id: String? = nil
    /// 仅调试用：附带一段文字，Mac 端会写进日志
    var dbg: String? = nil

    var json: Data {
        var s = "{\"t\":\"event\",\"k\":\"\(k.rawValue)\",\"dx\":\(dx),\"dy\":\(dy),\"v\":\(v)"
        if let p { s += ",\"p\":\"\(p.rawValue)\"" }
        if let id { s += ",\"id\":\"\(id)\"" }
        if let d = dbg {
            let esc = d.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            s += ",\"dbg\":\"\(esc)\""
        }
        s += "}"
        return s.data(using: .utf8) ?? Data()
    }
}

func encodeFrame(_ body: Data) -> Data {
    var length = UInt32(body.count).bigEndian
    var frame = Data(bytes: &length, count: 4)
    frame.append(body)
    return frame
}

struct Ack: Decodable {
    let t: String
    let id: String
}
