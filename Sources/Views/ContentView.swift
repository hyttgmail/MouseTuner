import SwiftUI

enum SidebarItem: Hashable {
    case device(String)
    case general
}

struct ContentView: View {
    @Environment(MouseManager.self) private var manager
    @State private var selection: SidebarItem?

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("鼠标") {
                    if manager.devices.isEmpty {
                        Text("未连接鼠标")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(manager.devices) { device in
                        Label {
                            Text(device.name)
                        } icon: {
                            IconTile(systemImage: "computermouse.fill", tint: .blue, size: 22)
                        }
                        .tag(SidebarItem.device(device.id))
                    }
                }
                Section {
                    Label {
                        Text("通用")
                    } icon: {
                        IconTile(systemImage: "gearshape.fill", tint: .gray, size: 22)
                    }
                    .tag(SidebarItem.general)
                }
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 300)
        } detail: {
            detail
        }
        .onAppear {
            if selection == nil {
                selection = manager.devices.first.map { .device($0.id) } ?? .general
            }
            manager.refreshPermissionStatus()
            // 窗口打开时显示在 Dock 和 ⌘Tab 里，关闭后只留菜单栏图标
            NSApp.setActivationPolicy(.regular)
            // 菜单栏 App 启动时系统不会主动激活它；新的 activate() 会被协作式激活拒绝，
            // 实测只有这个已弃用的版本能把窗口带到最前
            DispatchQueue.main.async { NSApp.activate(ignoringOtherApps: true) }
        }
        .onDisappear {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .device(let id):
            if let device = manager.devices.first(where: { $0.id == id }) {
                DeviceDetailView(device: device)
            } else {
                ContentUnavailableView(
                    "鼠标已断开",
                    systemImage: "computermouse",
                    description: Text("重新连接后，之前的设置会自动恢复。")
                )
            }
        case .general:
            GeneralSettingsView()
        case nil:
            ContentUnavailableView(
                "未检测到鼠标",
                systemImage: "computermouse",
                description: Text("连接鼠标后会自动显示在这里。")
            )
        }
    }
}

/// 系统设置风格的彩色圆角图标
struct IconTile: View {
    let systemImage: String
    let tint: Color
    let size: CGFloat

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.55, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(tint.gradient, in: .rect(cornerRadius: size * 0.28, style: .continuous))
    }
}
