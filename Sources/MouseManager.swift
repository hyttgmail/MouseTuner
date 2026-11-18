import AppKit
import ApplicationServices
import IOKit
import IOKit.hid
import IOKit.hidsystem
import Observation
import ServiceManagement
import os

/// 枚举鼠标、按设备写入 HID 参数、管理滚动翻转和权限。
@Observable
final class MouseManager {
    /// 与「系统设置 › 鼠标」的速度滑块一致（0…3）
    static let speedRange: ClosedRange<Double> = 0...3
    nonisolated static let logger = Logger(subsystem: "com.alphapengwang.MouseTuner", category: "devices")

    private(set) var devices: [MouseDevice] = []
    private(set) var settings: [String: MouseSettings]
    private(set) var isAccessibilityTrusted = AXIsProcessTrusted()
    private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    private(set) var conflictingApps: [String] = []

    /// 客户端的服务列表不会随插拔更新，每次刷新都换一个新的；旧客户端由仍在使用的 MouseDevice 持有
    @ObservationIgnored private var client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
    @ObservationIgnored private let scrollReverser = ScrollReverser()
    @ObservationIgnored private var notifyPort: IONotificationPortRef?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var permissionTimer: Timer?
    @ObservationIgnored private var didPromptForAccessibility = false

    init() {
        settings = Self.loadSettings()
        refresh()
        observeHotplug()
        observeWorkspace()
        updateConflictingApps()
    }

    // MARK: - 读取当前值

    func settings(for device: MouseDevice) -> MouseSettings {
        settings[device.id] ?? MouseSettings()
    }

    /// 是否有任何鼠标（包括暂未连接的）需要翻转滚动
    var wantsScrollReversal: Bool {
        settings.values.contains(where: \.reversesScrolling)
    }

    func pointerSpeed(of device: MouseDevice) -> Double {
        settings(for: device).pointerSpeed
            ?? currentFixedValue(of: device, key: Self.pointerKey)
            ?? systemFixedValue(HIDKey.mouseAcceleration, fallback: 45056)
    }

    func scrollSpeed(of device: MouseDevice) -> Double {
        settings(for: device).scrollSpeed
            ?? currentFixedValue(of: device, key: Self.scrollKey)
            ?? systemFixedValue(HIDKey.mouseScrollAcceleration, fallback: 20480)
    }

    /// 系统级「自然滚动」开关，对所有鼠标生效
    var systemUsesNaturalScrolling: Bool {
        let value = CFPreferencesCopyAppValue("com.apple.swipescrolldirection" as CFString, kCFPreferencesAnyApplication)
        return (value as? Bool) ?? true
    }

    // MARK: - 修改

    func update(_ device: MouseDevice, _ change: (inout MouseSettings) -> Void) {
        let old = settings(for: device)
        var new = old
        change(&new)
        guard new != old else { return }
        settings[device.id] = new.isCustomized ? new : nil
        saveSettings()
        apply(new, to: device)
        updateScrollReversal(prompt: new.reversesScrolling && !old.reversesScrolling)
    }

    func reset(_ device: MouseDevice) {
        guard let old = settings[device.id] else { return }
        settings[device.id] = nil
        saveSettings()
        restoreSystemValues(of: device, changedIn: old)
        updateScrollReversal()
    }

    /// 退出时把改过的鼠标恢复成系统值
    func restoreAllDevices() {
        scrollReverser.stop()
        for device in devices {
            if let old = settings[device.id] { restoreSystemValues(of: device, changedIn: old) }
        }
    }

    // MARK: - 设备枚举与写入

    func refresh() {
        client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
        devices = enumerateDevices()
        Self.logger.info("refresh: \(self.devices.map(\.name), privacy: .public)")
        for device in devices {
            if let saved = settings[device.id] { apply(saved, to: device) }
        }
        updateScrollReversal()
    }

    /// 设备插拔后 hidd 需要一点时间建好服务，并可能再写一次系统默认值，所以分两次重新套用。
    func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            self?.refresh()
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    private func enumerateDevices() -> [MouseDevice] {
        guard let array = IOHIDEventSystemClientCopyServices(client) else { return [] }
        var grouped: [String: [IOHIDServiceClient]] = [:]
        for service in array as! [IOHIDServiceClient] where isExternalMouse(service) {
            grouped[deviceID(of: service), default: []].append(service)
        }
        return grouped.map { id, services in
            let first = services[0]
            var senderIDs = Set<UInt64>()
            for service in services {
                guard let registryID = (IOHIDServiceClientGetRegistryID(service) as? NSNumber)?.uint64Value else { continue }
                senderIDs.insert(registryID)
                if let deviceID = Self.hidDeviceRegistryID(above: registryID) { senderIDs.insert(deviceID) }
            }
            return MouseDevice(
                id: id,
                name: property(first, kIOHIDProductKey) as? String ?? String(localized: "未知鼠标"),
                vendorID: (property(first, kIOHIDVendorIDKey) as? Int) ?? 0,
                productID: (property(first, kIOHIDProductIDKey) as? Int) ?? 0,
                transport: property(first, kIOHIDTransportKey) as? String ?? "",
                client: client,
                services: services,
                senderIDs: senderIDs
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// 只要主用途是鼠标的外接设备：排除触控板，也排除带指针接口的键盘（如 MX Keys）
    private func isExternalMouse(_ service: IOHIDServiceClient) -> Bool {
        (property(service, kIOHIDPrimaryUsagePageKey) as? Int) == kHIDPage_GenericDesktop
            && (property(service, kIOHIDPrimaryUsageKey) as? Int) == kHIDUsage_GD_Mouse
            && IOHIDServiceClientConformsTo(service, UInt32(kHIDPage_Digitizer), UInt32(kHIDUsage_Dig_TouchPad)) == 0
            && (property(service, kIOHIDBuiltInKey) as? Bool) != true
    }

    private func deviceID(of service: IOHIDServiceClient) -> String {
        let vendor = (property(service, kIOHIDVendorIDKey) as? Int) ?? 0
        let product = (property(service, kIOHIDProductIDKey) as? Int) ?? 0
        let name = property(service, kIOHIDProductKey) as? String ?? ""
        return "\(vendor):\(product):\(name)"
    }

    private func apply(_ settings: MouseSettings, to device: MouseDevice) {
        for service in device.services {
            if let speed = settings.pointerSpeed {
                setFixed(service, Self.pointerKey(service), speed)
            }
            if let speed = settings.scrollSpeed {
                setFixed(service, Self.scrollKey(service), speed)
            }
        }
    }

    private func restoreSystemValues(of device: MouseDevice, changedIn old: MouseSettings) {
        for service in device.services {
            if old.pointerSpeed != nil {
                let key = Self.pointerKey(service)
                IOHIDServiceClientSetProperty(service, key as CFString, systemValue(key) ?? 45056)
            }
            if old.scrollSpeed != nil {
                let key = Self.scrollKey(service)
                IOHIDServiceClientSetProperty(service, key as CFString, systemValue(key) ?? 20480)
            }
        }
    }

    // MARK: - 滚动翻转与权限

    private func updateScrollReversal(prompt: Bool = false) {
        var rules: [UInt64: ScrollReverser.Rule] = [:]
        for device in devices {
            let saved = settings(for: device)
            guard saved.reversesScrolling else { continue }
            for id in device.senderIDs {
                rules[id] = .init(vertical: saved.reverseVertical, horizontal: saved.reverseHorizontal)
            }
        }
        scrollReverser.setRules(rules)

        guard wantsScrollReversal else {
            scrollReverser.stop()
            stopPermissionPolling()
            return
        }
        isAccessibilityTrusted = AXIsProcessTrusted()
        if isAccessibilityTrusted, scrollReverser.start() {
            stopPermissionPolling()
        } else {
            if prompt && !didPromptForAccessibility { requestAccessibility() }
            startPermissionPolling()
        }
    }

    /// 「隐私与安全性」里的授权项名称：macOS 27 把「辅助功能」改名为「设备控制和数据访问」
    static var permissionName: String {
        if #available(macOS 27, *) {
            String(localized: "设备控制和数据访问")
        } else {
            String(localized: "辅助功能")
        }
    }

    func requestAccessibility() {
        didPromptForAccessibility = true
        // kAXTrustedCheckOptionPrompt 的字符串值；直接引用该全局变量在 Swift 6 下不是并发安全的
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        isAccessibilityTrusted = AXIsProcessTrustedWithOptions(options)
    }

    func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    func refreshPermissionStatus() {
        let trusted = AXIsProcessTrusted()
        guard trusted != isAccessibilityTrusted else { return }
        isAccessibilityTrusted = trusted
        updateScrollReversal()
    }

    private func startPermissionPolling() {
        guard permissionTimer == nil else { return }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPermissionStatus() }
        }
    }

    private func stopPermissionPolling() {
        permissionTimer?.invalidate()
        permissionTimer = nil
    }

    // MARK: - 登录时启动

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("MouseTuner: 修改登录项失败：\(error.localizedDescription)")
        }
        if SMAppService.mainApp.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: - 系统通知

    private func observeHotplug() {
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        notifyPort = port
        IONotificationPortSetDispatchQueue(port, .main)
        let context = Unmanaged.passUnretained(self).toOpaque()
        for type in [kIOFirstMatchNotification, kIOTerminatedNotification] {
            var iterator: io_iterator_t = 0
            let result = IOServiceAddMatchingNotification(
                port, type, IOServiceMatching("IOHIDEventService"), hotplugCallback, context, &iterator
            )
            // 必须先把迭代器取空，通知才会生效
            if result == KERN_SUCCESS { drain(iterator) }
        }
    }

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRefresh() }
        }
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateConflictingApps() }
            }
        }
    }

    /// 同类工具会写同一批 HID 参数，互相覆盖
    private func updateConflictingApps() {
        let known = ["SteerMouse", "LinearMouse", "USB Overdrive", "Mac Mouse Fix"]
        let running = NSWorkspace.shared.runningApplications.compactMap(\.localizedName)
        conflictingApps = known.filter { name in running.contains { $0.localizedCaseInsensitiveContains(name) } }
    }

    // MARK: - 工具方法

    private enum HIDKey {
        static let pointerAccelerationType = "HIDPointerAccelerationType"
        static let scrollAccelerationType = "HIDScrollAccelerationType"
        static let mouseAcceleration = "HIDMouseAcceleration"
        static let mouseScrollAcceleration = "HIDMouseScrollAcceleration"
    }

    /// 服务自己声明用哪个键控制加速度（鼠标通常是 HIDMouseAcceleration）
    private static func pointerKey(_ service: IOHIDServiceClient) -> String {
        IOHIDServiceClientCopyProperty(service, HIDKey.pointerAccelerationType as CFString) as? String ?? HIDKey.mouseAcceleration
    }

    private static func scrollKey(_ service: IOHIDServiceClient) -> String {
        IOHIDServiceClientCopyProperty(service, HIDKey.scrollAccelerationType as CFString) as? String ?? HIDKey.mouseScrollAcceleration
    }

    private func property(_ service: IOHIDServiceClient, _ key: String) -> CFTypeRef? {
        IOHIDServiceClientCopyProperty(service, key as CFString)
    }

    private func systemValue(_ key: String) -> NSNumber? {
        IOHIDEventSystemClientCopyProperty(client, key as CFString) as? NSNumber
    }

    /// HID 参数是 16.16 定点数
    private func setFixed(_ service: IOHIDServiceClient, _ key: String, _ value: Double) {
        IOHIDServiceClientSetProperty(service, key as CFString, NSNumber(value: Int((value * 65536).rounded())))
    }

    private func currentFixedValue(of device: MouseDevice, key: (IOHIDServiceClient) -> String) -> Double? {
        guard let service = device.services.first,
              let number = property(service, key(service)) as? NSNumber else { return nil }
        return (number.doubleValue / 65536).clamped(to: Self.speedRange)
    }

    private func systemFixedValue(_ key: String, fallback: Int) -> Double {
        (systemValue(key)?.doubleValue ?? Double(fallback)) / 65536
    }

    /// 找到服务上方的 IOHIDDevice，它的注册表 ID 也可能作为事件发送者
    private static func hidDeviceRegistryID(above serviceID: UInt64) -> UInt64? {
        var entry = IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(serviceID))
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }
        for _ in 0..<4 {
            var parent: io_registry_entry_t = 0
            guard IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent) == KERN_SUCCESS else { return nil }
            IOObjectRelease(entry)
            entry = parent
            if IOObjectConformsTo(entry, "IOHIDDevice") != 0 {
                var id: UInt64 = 0
                return IORegistryEntryGetRegistryEntryID(entry, &id) == KERN_SUCCESS ? id : nil
            }
        }
        return nil
    }

    private static let settingsKey = "deviceSettings"

    private static func loadSettings() -> [String: MouseSettings] {
        guard let data = UserDefaults.standard.data(forKey: settingsKey),
              let decoded = try? JSONDecoder().decode([String: MouseSettings].self, from: data) else { return [:] }
        return decoded
    }

    private func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Self.settingsKey)
        }
    }
}

private nonisolated func drain(_ iterator: io_iterator_t) {
    while case let object = IOIteratorNext(iterator), object != 0 {
        IOObjectRelease(object)
    }
}

private nonisolated func hotplugCallback(_ context: UnsafeMutableRawPointer?, _ iterator: io_iterator_t) {
    drain(iterator)
    MouseManager.logger.info("HID service added or removed")
    guard let context else { return }
    let manager = Unmanaged<MouseManager>.fromOpaque(context).takeUnretainedValue()
    // 通知端口挂在主队列上
    MainActor.assumeIsolated { manager.scheduleRefresh() }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
