import IOKit.hidsystem
import Foundation

/// 一只已连接的鼠标。一只鼠标可能对应多个 HID 事件服务。
struct MouseDevice: Identifiable {
    /// 厂商 ID + 产品 ID + 名称，用来跨重连、跨启动记住设置
    let id: String
    let name: String
    let vendorID: Int
    let productID: Int
    let transport: String
    /// 生成 `services` 的客户端。服务对象不会保留它，客户端一旦释放，再读服务属性就会访问已释放的内存，
    /// 所以由设备自己持有，界面里残留的旧设备值也能安全读取。
    let client: IOHIDEventSystemClient
    let services: [IOHIDServiceClient]
    /// 滚轮事件里可能出现的发送者 ID
    let senderIDs: Set<UInt64>
}

/// 单只鼠标的自定义设置；nil 表示不改动、沿用系统值。
struct MouseSettings: Codable, Equatable {
    var pointerSpeed: Double?
    var scrollSpeed: Double?
    var reverseVertical = false
    var reverseHorizontal = false

    var isCustomized: Bool { self != MouseSettings() }
    var reversesScrolling: Bool { reverseVertical || reverseHorizontal }
}
