import Foundation

enum SleepState: Equatable {
    case on, off, unknown
}

struct CommandResult {
    let status: Int32
    let stdout: String
    let stderr: String
}

enum SleepControl {
    /// `pmset -g` の出力から SleepDisabled を読む。行が無ければ OFF とみなす。
    static func parse(_ output: String) -> SleepState {
        for line in output.split(separator: "\n") {
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard fields.first == "SleepDisabled" else { continue }
            switch fields.dropFirst().first {
            case "1": return .on
            case "0": return .off
            default: return .unknown
            }
        }
        return .off
    }

    static func read() -> SleepState {
        guard let result = run("/usr/bin/pmset", ["-g"]), result.status == 0 else { return .unknown }
        return parse(result.stdout)
    }

    static func set(_ disabled: Bool) -> CommandResult? {
        // -n: パスワードを求めずに失敗させる。sudoers 未設定のとき GUI から入力待ちで固まらないため。
        run("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "-a", "disablesleep", disabled ? "1" : "0"], captureStderr: true)
    }

    static func run(_ path: String, _ arguments: [String], captureStderr: Bool = false) -> CommandResult? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        // 2 本のパイプを順に読むと、読んでいない側が満杯になった時点で子が書き込みで止まり、終了を待ち続ける。
        // 必要な側だけパイプにし、もう一方は捨てる。
        let pipe = Pipe()
        process.standardOutput = captureStderr ? FileHandle.nullDevice : pipe
        process.standardError = captureStderr ? pipe : FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        return CommandResult(
            status: process.terminationStatus,
            stdout: captureStderr ? "" : text,
            stderr: captureStderr ? text : ""
        )
    }
}
