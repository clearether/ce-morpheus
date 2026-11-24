import Foundation

enum PrivilegedResult: Equatable {
    case succeeded, cancelled, failed(String)
}

/// sudoers の許可設定を、osascript の管理者認証ダイアログ経由で作成・削除する。
/// 許可の主体とファイル名は数値 UID で表す。名前だと `ALL` や User_Alias と解釈され得るため、
/// またファイルを利用者ごとに分けて、ほかの利用者の設定を上書き・削除しないため。
enum Setup {
    static func rulePath(uid: uid_t) -> String {
        "/private/etc/sudoers.d/ce-morpheus-\(uid)"
    }

    static var rulePath: String { rulePath(uid: getuid()) }

    static var isInstalled: Bool { FileManager.default.fileExists(atPath: rulePath) }

    static func rule(uid: uid_t) -> String {
        "#\(uid) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1"
    }

    /// root で実行するシェル。外から入る値は整数の uid だけ。
    /// 一時ファイル名に `.` を含めるのは、sudo が `.` を含む名前を読み込まず、検査前の中身が有効にならないため。
    /// trap で、失敗・シグナルのどちらで終わっても一時ファイルを消す。mv の後は tmp を空にして、消す対象を無くす。
    static func installScript(uid: uid_t) -> String {
        let path = rulePath(uid: uid)
        return "tmp=$(/usr/bin/mktemp \(path).XXXXXX) || exit 1; "
            + "trap '/bin/rm -f \"$tmp\"' EXIT; trap 'exit 1' HUP INT TERM; "
            + "/usr/bin/printf '%s\\n' '\(rule(uid: uid))' > \"$tmp\""
            + " && /usr/sbin/chown root:wheel \"$tmp\" && /bin/chmod 0440 \"$tmp\""
            + " && /usr/sbin/visudo -cf \"$tmp\" 1>&2 && /bin/mv -f \"$tmp\" \(path) && tmp="
    }

    static func removeScript(uid: uid_t) -> String {
        "/bin/rm -f \(rulePath(uid: uid))"
    }

    static func appleScript(shell: String, prompt: String) -> String {
        "do shell script \(quoted(shell)) with prompt \(quoted(prompt)) with administrator privileges"
    }

    /// AppleScript の文字列リテラルにする。`\` を先に二重にしてから `"` をエスケープする。
    static func quoted(_ text: String) -> String {
        let escaped = text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    static func classify(status: Int32, stderr: String) -> PrivilegedResult {
        if status == 0 { return .succeeded }
        let message = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        // 認証ダイアログのキャンセルは AppleScript のエラー -128。文言は言語で変わるので番号で見る。
        return message.hasSuffix("(-128)") ? .cancelled : .failed(message)
    }

    private static func runPrivileged(_ shell: String, prompt: String) -> PrivilegedResult {
        let script = appleScript(shell: shell, prompt: prompt)
        guard let result = SleepControl.run("/usr/bin/osascript", ["-e", script], captureStderr: true) else {
            return .failed("osascript を起動できませんでした。")
        }
        return classify(status: result.status, stderr: result.stderr)
    }

    static func installPrompt(uid: uid_t) -> String {
        "ce-morpheus がスリープ設定を切り替えられるよう、許可設定（\(rulePath(uid: uid))）を作成します。"
    }

    static func removePrompt(uid: uid_t) -> String {
        "ce-morpheus の許可設定（\(rulePath(uid: uid))）を削除します。"
    }

    static func install() -> PrivilegedResult {
        let uid = getuid()
        return runPrivileged(installScript(uid: uid), prompt: installPrompt(uid: uid))
    }

    static func remove() -> PrivilegedResult {
        let uid = getuid()
        return runPrivileged(removeScript(uid: uid), prompt: removePrompt(uid: uid))
    }
}
