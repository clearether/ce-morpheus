import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let stateItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let toggleItem = NSMenuItem(title: "", action: #selector(toggle), keyEquivalent: "")
    private let removeItem = NSMenuItem(title: "許可設定を削除…", action: #selector(removeSetup), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "ログイン時に起動", action: #selector(toggleLoginItem), keyEquivalent: "")
    private var state: SleepState = .unknown
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        stateItem.isEnabled = false
        toggleItem.target = self
        removeItem.target = self
        loginItem.target = self
        menu.autoenablesItems = false
        menu.addItem(stateItem)
        menu.addItem(toggleItem)
        menu.addItem(.separator())
        menu.addItem(removeItem)
        menu.addItem(loginItem)
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
        removeItem.isHidden = !Setup.isInstalled
        let loginStatus = SMAppService.mainApp.status
        loginItem.state = loginStatus == .enabled ? .on : .off
        // 承認待ちはチェックが付かないが、選ぶと解除になるので、名前で伝える。
        loginItem.title = loginStatus == .requiresApproval ? "ログイン時に起動（承認待ち・選ぶと解除）" : "ログイン時に起動"
    }

    @objc private func toggleLoginItem() {
        defer { refresh() }
        let service = SMAppService.mainApp
        do {
            switch service.status {
            case .enabled, .requiresApproval:
                try service.unregister()
            default:
                try service.register()
                if service.status == .requiresApproval {
                    showAlert("ログイン項目の許可が必要です", "システム設定の「ログイン項目」で ce-morpheus を許可してください。")
                }
            }
        } catch {
            showAlert("ログイン時の起動を切り替えられませんでした", error.localizedDescription)
        }
    }

    @objc private func toggle() {
        defer { refresh() }
        let disable = state != .on
        let first = SleepControl.set(disable)
        if first?.status == 0 { return }
        let reason = first?.stderr.trimmingCharacters(in: .whitespacesAndNewlines) ?? "sudo を起動できませんでした。"

        // 設定済みなら作り直しても直らないので、理由だけを示す。
        if Setup.isInstalled {
            showAlert("切り替えに失敗しました", reason)
            return
        }
        guard confirm(
            "初回の設定が必要です",
            """
            管理者のパスワードを 1 回入力すると、このアプリがスリープ設定を切り替えられるようになります。

            許可する内容: ユーザー「\(NSUserName())」（UID \(getuid())）に、/usr/bin/pmset -a disablesleep 0 と 1 の 2 コマンドだけをパスワードなしで許可します。設定ファイルは \(Setup.rulePath) です。

            切り替えに失敗した理由: \(reason)
            """,
            button: "設定する"
        ) else { return }
        switch Setup.install() {
        case .cancelled: return
        case .failed(let detail):
            showAlert("許可設定の作成に失敗しました", detail)
            return
        case .succeeded: break
        }
        let retry = SleepControl.set(disable)
        if retry?.status != 0 {
            showAlert("許可設定は作成しましたが、切り替えに失敗しました", retry?.stderr ?? "sudo を起動できませんでした。")
        }
    }

    @objc private func removeSetup() {
        defer { refresh() }
        guard confirm(
            "許可設定を削除しますか？",
            """
            \(Setup.rulePath) を削除します。管理者のパスワードが必要です。

            現在の ON/OFF は変わりません。ON のまま削除すると、OFF に戻すときにもう一度設定が必要になります。
            """,
            button: "削除する"
        ) else { return }
        if case .failed(let detail) = Setup.remove() {
            showAlert("許可設定の削除に失敗しました", detail)
        }
    }

    private func confirm(_ title: String, _ text: String, button: String) -> Bool {
        let alert = makeAlert(title, text)
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "キャンセル")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func showAlert(_ title: String, _ text: String) {
        _ = makeAlert(title, text).runModal()
    }

    private func makeAlert(_ title: String, _ text: String) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // メニューバー常駐アプリは前面にいないため、アラートが他のウインドウの裏に隠れないようにする。
        NSApp.activate()
        return alert
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
