import SwiftUI

/// 布局对齐 macOS 27「系统设置 › 鼠标」：一组设置、刻度滑杆、按钮放在分组下方
struct DeviceDetailView: View {
    @Environment(MouseManager.self) private var manager
    let device: MouseDevice

    private var saved: MouseSettings { manager.settings(for: device) }

    var body: some View {
        Form {
            if !manager.conflictingApps.isEmpty {
                Section {
                    NoticeRow(
                        systemImage: "exclamationmark.triangle.fill",
                        tint: .yellow,
                        title: "\(manager.conflictingApps.formatted(.list(type: .and))) 正在运行",
                        message: "它会修改同样的鼠标参数，可能覆盖这里的设置。建议先退出它。"
                    )
                }
            }

            Section {
                SpeedSlider(
                    title: "追踪速度",
                    value: binding(get: manager.pointerSpeed(of:), set: { $0.pointerSpeed = $1 })
                )
                SpeedSlider(
                    title: "滚动速度",
                    value: binding(get: manager.scrollSpeed(of:), set: { $0.scrollSpeed = $1 })
                )
            }

            Section {
                Toggle(isOn: binding(get: { _ in saved.reverseVertical }, set: { $0.reverseVertical = $1 })) {
                    Text("反转垂直滚动")
                    manager.systemUsesNaturalScrolling ? Text("这只鼠标不使用自然滚动") : Text("这只鼠标使用自然滚动")
                }
                Toggle(isOn: binding(get: { _ in saved.reverseHorizontal }, set: { $0.reverseHorizontal = $1 })) {
                    Text("反转水平滚动")
                    Text("适用于侧边滚轮或横向滚动")
                }
                if saved.reversesScrolling && !manager.isAccessibilityTrusted {
                    NoticeRow(
                        systemImage: "hand.raised.fill",
                        tint: .orange,
                        title: "需要「\(MouseManager.permissionName)」权限",
                        message: "授权后立即生效。"
                    ) {
                        Button("打开系统设置") { manager.openAccessibilitySettings() }
                    }
                }
            } footer: {
                HStack {
                    Spacer()
                    Button("恢复默认") { manager.reset(device) }
                        .disabled(!saved.isCustomized)
                }
                .padding(.top, 8)
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle(device.name)
    }

    private func binding<Value>(
        get: @escaping (MouseDevice) -> Value,
        set: @escaping (inout MouseSettings, Value) -> Void
    ) -> Binding<Value> {
        Binding(
            get: { get(device) },
            set: { newValue in manager.update(device) { set(&$0, newValue) } }
        )
    }
}

/// 与系统设置一致的刻度滑杆：两端标「慢 / 快」，不显示数值
private struct SpeedSlider: View {
    let title: LocalizedStringKey
    @Binding var value: Double

    private static let ticks = Array(stride(from: MouseManager.speedRange.lowerBound,
                                            through: MouseManager.speedRange.upperBound,
                                            by: 0.375))

    var body: some View {
        Slider(value: $value, in: MouseManager.speedRange) {
            Text(title)
        } ticks: {
            SliderTickContentForEach(Self.ticks, id: \.self) { tick in
                if tick == MouseManager.speedRange.lowerBound {
                    SliderTick("慢", tick)
                } else if tick == MouseManager.speedRange.upperBound {
                    SliderTick("快", tick)
                } else {
                    SliderTick(tick)
                }
            }
        }
    }
}

struct NoticeRow<Accessory: View>: View {
    let systemImage: String
    let tint: Color
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            accessory
        }
    }
}

extension NoticeRow where Accessory == EmptyView {
    init(systemImage: String, tint: Color, title: LocalizedStringKey, message: LocalizedStringKey) {
        self.init(systemImage: systemImage, tint: tint, title: title, message: message) { EmptyView() }
    }
}
