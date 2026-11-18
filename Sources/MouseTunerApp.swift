import AppKit
import SwiftUI

@main
struct MouseTunerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("MouseTuner", id: "main") {
            ContentView()
                .environment(appDelegate.manager)
                .frame(minWidth: 700, minHeight: 500)
        }
        .defaultSize(width: 800, height: 580)
        .windowResizability(.contentMinSize)

        MenuBarExtra("MouseTuner", systemImage: "computermouse") {
            MenuBarMenu()
                .environment(appDelegate.manager)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 切换语言后自动重启时为 true：新实例马上会重新套用设置，退出时就不必先恢复系统默认
    static var isRelaunching = false

    let manager = MouseManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 登录时自动启动的情况下只待在菜单栏，不弹窗口
        let event = NSAppleEventManager.shared().currentAppleEvent
        let launchedAtLogin = event?.eventID == kAEOpenApplication
            && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        if launchedAtLogin {
            DispatchQueue.main.async {
                NSApp.windows.filter { $0.identifier?.rawValue.hasPrefix("main") == true }.forEach { $0.close() }
            }
        }
    }

    /// 关掉窗口后继续在菜单栏运行，鼠标重连时才能重新套用设置
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard !Self.isRelaunching else { return }
        manager.restoreAllDevices()
    }
}
