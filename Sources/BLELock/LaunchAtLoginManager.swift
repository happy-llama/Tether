import Foundation

class LaunchAtLoginManager {
    private let label    = "com.blelock"
    private let plistURL = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/LaunchAgents/com.blelock.plist")

    var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    func enable(executablePath: String) throws {
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executablePath],
            "RunAtLoad": true,
            "KeepAlive": true
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: plistURL)
        runLaunchctl("load", plistURL.path)
    }

    func disable() {
        runLaunchctl("unload", plistURL.path)
        try? FileManager.default.removeItem(at: plistURL)
    }

    private func runLaunchctl(_ command: String, _ path: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = [command, path]
        try? task.run()
        task.waitUntilExit()
    }
}
