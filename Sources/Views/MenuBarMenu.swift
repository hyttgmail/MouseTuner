import SwiftUI

struct MenuBarMenu: View {
    @Environment(MouseManager.self) private var manager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("打开 MouseTuner…") {
            openWindow(id: "main")
            NSApp.activate()
        }

        Divider()

        if manager.devices.isEmpty {
            Text("未检测到鼠标")
        } else {
            Section("已连接的鼠标") {
                ForEach(manager.devices) { device in
                    if manager.settings[device.id] != nil {
                        Text("\(device.name)（已自定义）")
                    } else {
                        Text(verbatim: device.name)
                    }
                }
            }
        }

        Divider()

        Toggle("登录时自动启动", isOn: Binding(
            get: { manager.launchAtLogin },
            set: { manager.setLaunchAtLogin($0) }
        ))

        Divider()

        Button("退出 MouseTuner") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
