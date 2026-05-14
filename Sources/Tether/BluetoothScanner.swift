import Foundation

enum BluetoothScanner {
    static func scanPairedDevices() -> [BTDevice] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        task.arguments = ["SPBluetoothDataType"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        guard (try? task.run()) != nil else { return [] }
        task.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return parseDevices(from: output)
    }

    private static func parseDevices(from output: String) -> [BTDevice] {
        var devices: [BTDevice] = []
        var currentName: String?
        var inDeviceSection = false

        for line in output.components(separatedBy: "\n") {
            let indent = line.prefix(while: { $0 == " " }).count
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if indent == 6 {
                inDeviceSection = trimmed == "Connected:" || trimmed == "Not Connected:"
                currentName = nil
                continue
            }

            guard inDeviceSection else { continue }

            if indent == 10, trimmed.hasSuffix(":") {
                currentName = String(trimmed.dropLast())
                continue
            }

            if indent == 14, let name = currentName, trimmed.hasPrefix("Address:") {
                let addr = trimmed.dropFirst("Address:".count).trimmingCharacters(in: .whitespaces)
                if !addr.isEmpty {
                    devices.append(BTDevice(name: name, address: addr.uppercased()))
                    currentName = nil
                }
            }
        }

        return devices
    }
}
