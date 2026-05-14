import Foundation

class BluetoothMonitor {
    private let pollInterval: TimeInterval = 8
    let gracePeriod: TimeInterval
    let rssiThreshold: Int
    var lockMode: LockMode = .allDevicesLeave
    private let logFile = "/tmp/tether_debug.log"

    // Require this many consecutive missed polls before treating a device as away.
    // Absorbs transient BLE advertisement gaps (e.g. Apple Watch power-saving pauses).
    private let missThreshold = 2
    private var missCounts: [String: Int] = [:]

    private(set) var watchedAddresses: [String] = []
    var deviceNames: [String: String] = [:]

    private var timer: Timer?
    private var disconnectTime: Date?
    private var wasNearby = false

    var onStatusChanged: ((String) -> Void)?
    var onLockTriggered: (() -> Void)?

    init(gracePeriod: TimeInterval = 30, rssiThreshold: Int = -70) {
        self.gracePeriod = gracePeriod
        self.rssiThreshold = rssiThreshold
        log("Tether started, threshold=\(rssiThreshold), grace=\(Int(gracePeriod))s, missThreshold=\(missThreshold)")
    }

    func setWatchedAddresses(_ addresses: [String]) {
        watchedAddresses = addresses
        missCounts = missCounts.filter { addresses.contains($0.key) }
        log("Watching: \(addresses.joined(separator: ", "))")
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(timer!, forMode: .common)
        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        disconnectTime = nil
        wasNearby = false
        missCounts = [:]
        log("Monitor stopped")
    }

    private func poll() {
        guard !watchedAddresses.isEmpty else {
            onStatusChanged?(L("status.no_device_selected"))
            return
        }

        let profileData = runSystemProfiler()
        var nearbyRSSIs: [(String, Int)] = []
        var awayAddresses: [String] = []
        var pendingAddresses: [String] = []

        for address in watchedAddresses {
            if isConnected(in: profileData, address: address) {
                nearbyRSSIs.append((address, 0))
                missCounts[address] = 0
            } else if let rssi = parseRSSI(from: profileData, address: address), rssi >= rssiThreshold {
                nearbyRSSIs.append((address, rssi))
                missCounts[address] = 0
            } else {
                let count = (missCounts[address] ?? 0) + 1
                missCounts[address] = count
                if count >= missThreshold {
                    awayAddresses.append(address)
                } else {
                    pendingAddresses.append(address)
                }
            }
        }

        let nearby: Bool
        switch lockMode {
        case .allDevicesLeave:
            nearby = (nearbyRSSIs.count + pendingAddresses.count) > 0
        case .anyDeviceLeaves:
            nearby = awayAddresses.isEmpty
        }

        let rssiDesc = nearbyRSSIs.map { addr, rssi -> String in
            let name = deviceNames[addr] ?? String(addr.suffix(5))
            return rssi == 0 ? "\(name):connected" : "\(name):\(rssi)"
        }.joined(separator: " ")

        log("mode=\(lockMode.rawValue) nearby=\(nearby) nearbyRSSIs=\(nearbyRSSIs) away=\(awayAddresses) pending=\(pendingAddresses)")

        if nearby {
            if !wasNearby {
                onStatusChanged?(L("status.device_detected"))
                log("→ First detection, start monitoring")
            } else {
                onStatusChanged?(L("status.monitoring", rssiDesc))
            }
            wasNearby = true
            disconnectTime = nil
        } else if wasNearby {
            if disconnectTime == nil {
                disconnectTime = Date()
                log("→ Devices left, starting \(Int(gracePeriod))s grace timer")
                onStatusChanged?(L("status.device_left", Int(gracePeriod)))
            } else if let dt = disconnectTime, Date().timeIntervalSince(dt) >= gracePeriod {
                let freshData = runSystemProfiler()
                let stillAway = !watchedAddresses.contains {
                    isConnected(in: freshData, address: $0) ||
                    (parseRSSI(from: freshData, address: $0).map { $0 >= rssiThreshold } ?? false)
                }
                guard stillAway else {
                    log("→ Device returned before lock, cancelling")
                    disconnectTime = nil
                    wasNearby = true
                    return
                }
                log("→ Grace period expired → LOCKING")
                onStatusChanged?(L("status.locking"))
                onLockTriggered?()
                disconnectTime = nil
                wasNearby = false
            } else if let dt = disconnectTime {
                let remaining = Int(gracePeriod - Date().timeIntervalSince(dt))
                onStatusChanged?(L("status.device_left", remaining))
            }
        } else {
            onStatusChanged?(L("status.waiting"))
        }
    }

    private func runSystemProfiler() -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        task.arguments = ["SPBluetoothDataType"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        guard (try? task.run()) != nil else { return "" }
        task.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    private func normalizeAddress(_ addr: String) -> String {
        addr.uppercased().replacingOccurrences(of: "-", with: ":").replacingOccurrences(of: ".", with: ":")
    }

    private func isConnected(in output: String, address: String) -> Bool {
        let needle = normalizeAddress(address)
        var inConnected = false
        for line in output.components(separatedBy: "\n") {
            let indent = line.prefix(while: { $0 == " " }).count
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if indent == 6 {
                inConnected = trimmed == "Connected:"
                continue
            }
            if inConnected && indent == 14 && trimmed.hasPrefix("Address:") {
                let addr = trimmed.dropFirst("Address:".count).trimmingCharacters(in: .whitespaces)
                if normalizeAddress(addr) == needle { return true }
            }
        }
        return false
    }

    private func parseRSSI(from output: String, address: String) -> Int? {
        let needle = normalizeAddress(address)
        let lines = output.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() {
            guard normalizeAddress(line).contains(needle) else { continue }
            let start = max(0, i - 3)
            let end   = min(lines.count - 1, i + 3)
            for j in start...end {
                if lines[j].contains("RSSI:") {
                    let parts = lines[j].components(separatedBy: ":")
                    if let last = parts.last, let rssi = Int(last.trimmingCharacters(in: .whitespaces)) {
                        return rssi
                    }
                }
            }
        }
        return nil
    }

    private func log(_ msg: String) {
        let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let line = "[\(ts)] \(msg)\n"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: logFile) {
            if let fh = FileHandle(forWritingAtPath: logFile) {
                fh.seekToEndOfFile()
                fh.write(data)
                fh.closeFile()
            }
        } else {
            try? data.write(to: URL(fileURLWithPath: logFile))
        }
    }
}
