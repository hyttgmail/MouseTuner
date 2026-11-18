import CoreGraphics
import Foundation
import os

/// 在会话级事件流里拦截滚轮事件，只翻转指定鼠标的滚动方向。
/// 事件回调运行在独立线程上，避免主线程卡顿时拖慢全系统滚动。
nonisolated final class ScrollReverser: @unchecked Sendable {
    struct Rule: Sendable, Equatable {
        var vertical: Bool
        var horizontal: Bool
    }

    private static let logger = Logger(subsystem: "com.alphapengwang.MouseTuner", category: "scroll")

    /// 事件的发送者 ID（HID 服务的注册表 ID）。这个字段没有写进 CGEventField 的头文件，
    /// 但通过公开的 getIntegerValueField 读取，不依赖私有符号，App Store 版本也能用。
    private static let senderIDField = CGEventField(rawValue: 87)!

    /// 发送者 ID（HID 服务或设备的注册表 ID）→ 翻转规则
    private let rules = OSAllocatedUnfairLock<[UInt64: Rule]>(initialState: [:])
    private let lock = NSLock()
    private var tap: CFMachPort?

    var isRunning: Bool { lock.withLock { tap != nil } }

    func setRules(_ newRules: [UInt64: Rule]) {
        rules.withLock { $0 = newRules }
    }

    /// 没有「辅助功能」权限时创建事件监听会失败，返回 false。
    @discardableResult
    func start() -> Bool {
        if isRunning { return true }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.scrollWheel.rawValue),
            callback: scrollEventCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        lock.withLock { self.tap = tap }
        nonisolated(unsafe) let port = tap
        let thread = Thread {
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: port, enable: true)
            // 端口失效后 run loop 没有输入源，会自动返回，线程随之结束
            CFRunLoopRun()
        }
        thread.name = "MouseTuner.ScrollTap"
        thread.qualityOfService = .userInteractive
        thread.start()
        return true
    }

    func stop() {
        let tap = lock.withLock {
            defer { self.tap = nil }
            return self.tap
        }
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        CFMachPortInvalidate(tap)
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap = lock.withLock({ tap }) {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        case .scrollWheel:
            // 程序合成的滚动事件没有发送者，直接放行
            let sender = UInt64(bitPattern: event.getIntegerValueField(Self.senderIDField))
            guard sender != 0 else { return }
            guard let rule = rules.withLock({ $0[sender] }) else {
                // 排查用：log stream --level debug --predicate 'subsystem == "com.alphapengwang.MouseTuner"'
                Self.logger.debug("scroll from unmatched sender \(sender, privacy: .public)")
                return
            }
            if rule.vertical {
                Self.negate(event, .scrollWheelEventDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventPointDeltaAxis1)
            }
            if rule.horizontal {
                Self.negate(event, .scrollWheelEventDeltaAxis2, .scrollWheelEventFixedPtDeltaAxis2, .scrollWheelEventPointDeltaAxis2)
            }
        default:
            break
        }
    }

    /// 行、定点、像素三种增量都要取反，否则不同 App 读到的方向不一致。
    private static func negate(_ event: CGEvent, _ line: CGEventField, _ fixed: CGEventField, _ point: CGEventField) {
        let lineDelta = event.getIntegerValueField(line)
        let fixedDelta = event.getDoubleValueField(fixed)
        let pointDelta = event.getIntegerValueField(point)
        event.setIntegerValueField(line, value: -lineDelta)
        event.setDoubleValueField(fixed, value: -fixedDelta)
        event.setIntegerValueField(point, value: -pointDelta)
    }
}

private nonisolated func scrollEventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if let userInfo {
        Unmanaged<ScrollReverser>.fromOpaque(userInfo).takeUnretainedValue().handle(type: type, event: event)
    }
    return Unmanaged.passUnretained(event)
}
