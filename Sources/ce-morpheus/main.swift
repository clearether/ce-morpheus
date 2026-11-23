import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let stateItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let toggleItem = NSMenuItem(title: "", action: #selector(toggle), keyEquivalent: "")
    private var state: SleepState = .unknown
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        stateItem.isEnabled = false
        toggleItem.target = self
        menu.autoenablesItems = false
        menu.addItem(stateItem)
        menu.addItem(toggleItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.delegate = self
        statusItem.menu = menu

        refresh()
        // 外部で pmset の値が変わってもアイコンを追従させる。
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        refresh()
    }

    private func refresh() {
        state = SleepControl.read()
        let imageName: String
        let fallbackTitle: String
        let description: String
        switch state {
        case .on:
            imageName = "ampoule-on"
            fallbackTitle = "ON"
            description = "スリープ抑止: ON（蓋を閉じても動作）"
            toggleItem.title = "OFF にする"
        case .off:
            imageName = "ampoule-off"
            fallbackTitle = "OFF"
            description = "スリープ抑止: OFF"
            toggleItem.title = "ON にする"
        case .unknown:
            imageName = "ampoule-unknown"
            fallbackTitle = "?"
            description = "スリープ抑止: 不明（pmset を読めません）"
            toggleItem.title = "ON にする"
        }
        stateItem.title = description
        let image = Bundle.main.image(forResource: imageName)
        image?.isTemplate = true
        image?.accessibilityDescription = description
        statusItem.button?.image = image
        // 画像が読めないとき、項目が見えない空白にならないよう文字で代替する。
        statusItem.button?.title = image == nil ? fallbackTitle : ""
        statusItem.length = image == nil ? NSStatusItem.variableLength : NSStatusItem.squareLength
        statusItem.button?.setAccessibilityLabel(description)
        statusItem.button?.toolTip = description
    }

    @objc private func toggle() {
        let result = SleepControl.set(state != .on)
        refresh()
        if let result, result.status == 0 { return }
        showSetupAlert(detail: result?.stderr ?? "sudo を起動できませんでした。")
    }

    private func showSetupAlert(detail: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "切り替えに失敗しました（設定が必要です）"
        alert.informativeText = """
            sudoers の設定が必要な可能性があります。README の「sudoers の設定」の手順を確認してください。

            \(detail.trimmingCharacters(in: .whitespacesAndNewlines))
            """
        // メニューバー常駐アプリは前面にいないため、アラートが他のウインドウの裏に隠れないようにする。
        NSApp.activate()
        alert.runModal()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
