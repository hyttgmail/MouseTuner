import AppKit

/// 界面语言。macOS 给单个 App 指定语言的方式，是在 App 自己的偏好里写 AppleLanguages，重新启动后生效。
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    var id: Self { self }

    /// 本次启动时实际生效的设置，用来判断改动后是否需要重启
    static let atLaunch = current

    /// 只读 App 自己域里的值；`UserDefaults.standard` 会混入全局的系统语言列表
    static var current: AppLanguage {
        let domain = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
        let codes = domain?["AppleLanguages"] as? [String]
        return codes?.first.flatMap(AppLanguage.init(rawValue:)) ?? .system
    }

    func apply() {
        if self == .system {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([rawValue], forKey: "AppleLanguages")
        }
    }

    /// 等当前进程完全退出后再打开自己，避免新旧两个实例同时拦截滚轮
    static func relaunch() {
        AppDelegate.isRelaunching = true
        let script = Process()
        script.executableURL = URL(fileURLWithPath: "/bin/sh")
        script.arguments = [
            "-c", "while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$0\"",
            Bundle.main.bundlePath,
        ]
        try? script.run()
        NSApp.terminate(nil)
    }
}
