import SwiftUI

struct GeneralSettingsView: View {
    @Environment(MouseManager.self) private var manager
    @State private var language = AppLanguage.current

    /// App Store 审核要求 App 内能打开隐私政策（5.1.1）和联系方式（1.5），网址和商店页里填的一致
    private static let privacyURL = URL(string: "https://alphapengwang.com/apps/mousetuner/privacy")!
    private static let supportURL = URL(string: "https://alphapengwang.com/apps/mousetuner/support")!

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    var body: some View {
        Form {
            Section {
                Toggle("登录时自动启动", isOn: Binding(
                    get: { manager.launchAtLogin },
                    set: { manager.setLaunchAtLogin($0) }
                ))
            } footer: {
                Text("MouseTuner 需要保持运行：鼠标重新连接或电脑唤醒后，它会自动重新套用设置。")
                    .foregroundStyle(.secondary)
            }

            Section {
                // 语言名称始终用各自的语言显示，方便看不懂当前界面的人找到自己的语言
                Picker("语言", selection: $language) {
                    Text("跟随系统").tag(AppLanguage.system)
                    Text(verbatim: "简体中文").tag(AppLanguage.simplifiedChinese)
                    Text(verbatim: "English").tag(AppLanguage.english)
                }
                .onChange(of: language) { _, newValue in newValue.apply() }
                if language != AppLanguage.atLaunch {
                    HStack {
                        Text("重新启动 MouseTuner 后生效。")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("立即重新启动") { AppLanguage.relaunch() }
                    }
                }
            }

            Section {
                LabeledContent(MouseManager.permissionName) {
                    if manager.isAccessibilityTrusted {
                        Label("已授权", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("前往授权") {
                            manager.requestAccessibility()
                            manager.openAccessibilitySettings()
                        }
                    }
                }
            } footer: {
                Text("只有「反转滚动方向」需要「\(MouseManager.permissionName)」权限，调节速度不需要。")
                    .foregroundStyle(.secondary)
            }

            Section {
            } footer: {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("版本 \(version) · 退出后，调整过的鼠标会恢复为系统默认设置。")
                            .foregroundStyle(.secondary)
                        HStack(spacing: 12) {
                            Link("隐私政策", destination: Self.privacyURL)
                            Link("技术支持", destination: Self.supportURL)
                        }
                    }
                    Spacer()
                    Button("退出 MouseTuner") { NSApp.terminate(nil) }
                }
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle("通用")
    }
}
