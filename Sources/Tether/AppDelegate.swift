import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var monitor: BluetoothMonitor!
    private var isEnabled = true
    private var allDevices: [BTDevice] = []
    private var deviceNames: [String: String] = [:]

    private let loginManager = LaunchAtLoginManager()

    private var statusMenuItem: NSMenuItem!
    private var toggleMenuItem: NSMenuItem!
    private var launchAtLoginItem: NSMenuItem!
    private var deviceMenu: NSMenu!
    private var graceMenu: NSMenu!
    private var thresholdMenu: NSMenu!
    private var lockModeMenu: NSMenu!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupMenuBar()
        syncLaunchAtLoginItem()
        loadDevicesAndStart()
    }

    // MARK: - Monitor

    private func makeMonitor() -> BluetoothMonitor {
        let m = BluetoothMonitor(gracePeriod: Settings.gracePeriod, rssiThreshold: Settings.rssiThreshold)
        m.lockMode    = Settings.lockMode
        m.deviceNames = deviceNames
        m.onStatusChanged = { [weak self] status in
            DispatchQueue.main.async { self?.statusMenuItem.title = status }
        }
        m.onLockTriggered = { [weak self] in
            DispatchQueue.main.async { ScreenLocker.lock() }
        }
        return m
    }

    private func restartMonitor() {
        monitor?.stop()
        monitor = makeMonitor()
        monitor.setWatchedAddresses(Settings.selectedAddresses)
        if isEnabled { monitor.start() }
        syncAllMenuStates()
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let img = NSImage(systemSymbolName: "lock.circle.fill", accessibilityDescription: nil)
        img?.isTemplate = true
        statusItem.button?.image = img

        let menu = NSMenu()

        statusMenuItem = NSMenuItem(title: L("status.starting"), action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())

        let lockNow = NSMenuItem(title: L("menu.lock_now"), action: #selector(lockNow), keyEquivalent: "l")
        lockNow.target = self
        menu.addItem(lockNow)

        toggleMenuItem = NSMenuItem(title: L("menu.disable_monitoring"), action: #selector(toggleMonitoring), keyEquivalent: "")
        toggleMenuItem.target = self
        menu.addItem(toggleMenuItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: L("menu.settings"), action: nil, keyEquivalent: "")
        let settingsMenu = NSMenu()

        settingsMenu.addItem(makeSubmenuItem(title: L("menu.watched_devices")) { self.deviceMenu = $0 })
        settingsMenu.addItem(makeSubmenuItem(title: L("menu.lock_delay"), items: [
            (L("delay.10s"), 10), (L("delay.30s"), 30), (L("delay.60s"), 60)
        ], action: #selector(setGracePeriod(_:)), menu: &graceMenu))
        settingsMenu.addItem(makeSubmenuItem(title: L("menu.sensitivity"), items: [
            (L("rssi.1m"),  -55),
            (L("rssi.3m"),  -65),
            (L("rssi.5m"),  -70),
            (L("rssi.10m"), -75)
        ], action: #selector(setThreshold(_:)), menu: &thresholdMenu))
        settingsMenu.addItem(makeLockModeItem())
        settingsMenu.addItem(.separator())

        launchAtLoginItem = NSMenuItem(title: L("menu.launch_at_login"), action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginItem.target = self
        settingsMenu.addItem(launchAtLoginItem)

        settingsItem.submenu = settingsMenu
        menu.addItem(settingsItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L("menu.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    private func makeSubmenuItem(title: String, configure: (NSMenu) -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        configure(submenu)
        item.submenu = submenu
        return item
    }

    private func makeSubmenuItem(title: String, items: [(String, Int)], action: Selector, menu: inout NSMenu?) -> NSMenuItem {
        let parentItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for (label, tag) in items {
            let item = NSMenuItem(title: label, action: action, keyEquivalent: "")
            item.tag = tag; item.target = self
            submenu.addItem(item)
        }
        menu = submenu
        parentItem.submenu = submenu
        return parentItem
    }

    private func makeLockModeItem() -> NSMenuItem {
        let parentItem = NSMenuItem(title: L("menu.lock_condition"), action: nil, keyEquivalent: "")
        lockModeMenu = NSMenu()
        for (title, mode) in [(L("lock_mode.all_leave"), LockMode.allDevicesLeave),
                               (L("lock_mode.any_leave"), LockMode.anyDeviceLeaves)] {
            let item = NSMenuItem(title: title, action: #selector(setLockMode(_:)), keyEquivalent: "")
            item.representedObject = mode.rawValue
            item.target = self
            lockModeMenu.addItem(item)
        }
        parentItem.submenu = lockModeMenu
        return parentItem
    }

    private func syncAllMenuStates() {
        graceMenu.items.forEach { $0.state = ($0.tag == Int(Settings.gracePeriod)) ? .on : .off }
        thresholdMenu.items.forEach { $0.state = ($0.tag == Settings.rssiThreshold) ? .on : .off }
        lockModeMenu.items.forEach { $0.state = ($0.representedObject as? String == Settings.lockMode.rawValue) ? .on : .off }
        syncLaunchAtLoginItem()
    }

    private func syncLaunchAtLoginItem() {
        launchAtLoginItem?.state = loginManager.isEnabled ? .on : .off
    }

    // MARK: - Device Loading

    private func loadDevicesAndStart() {
        DispatchQueue.global().async { [weak self] in
            guard let self else { return }
            let devices = BluetoothScanner.scanPairedDevices()
            let saved = Set(Settings.selectedAddresses)
            DispatchQueue.main.async {
                self.allDevices = devices
                self.deviceNames = Dictionary(devices.map { ($0.address, $0.name) },
                                              uniquingKeysWith: { f, _ in f })
                self.rebuildDeviceMenu(selected: saved)
                self.restartMonitor()
            }
        }
    }

    private func rebuildDeviceMenu(selected: Set<String>) {
        deviceMenu.removeAllItems()
        guard !allDevices.isEmpty else {
            deviceMenu.addItem(NSMenuItem(title: L("device.none_found"), action: nil, keyEquivalent: ""))
            return
        }
        let refresh = NSMenuItem(title: L("device.rescan"), action: #selector(refreshDevices), keyEquivalent: "r")
        refresh.target = self
        deviceMenu.addItem(refresh)
        deviceMenu.addItem(.separator())
        for device in allDevices {
            let item = NSMenuItem(title: device.name, action: #selector(toggleDevice(_:)), keyEquivalent: "")
            item.representedObject = device.address
            item.state = selected.contains(device.address) ? .on : .off
            item.target = self
            deviceMenu.addItem(item)
        }
    }

    // MARK: - Actions

    @objc private func toggleDevice(_ sender: NSMenuItem) {
        guard let address = sender.representedObject as? String else { return }
        var saved = Set(Settings.selectedAddresses)
        if saved.contains(address) { saved.remove(address); sender.state = .off }
        else                        { saved.insert(address);  sender.state = .on  }
        Settings.selectedAddresses = Array(saved)
        monitor.setWatchedAddresses(Array(saved))
    }

    @objc private func refreshDevices() {
        statusMenuItem.title = L("status.scanning")
        DispatchQueue.global().async { [weak self] in
            guard let self else { return }
            let devices = BluetoothScanner.scanPairedDevices()
            let saved = Set(Settings.selectedAddresses)
            DispatchQueue.main.async {
                self.allDevices = devices
                self.deviceNames = Dictionary(devices.map { ($0.address, $0.name) },
                                              uniquingKeysWith: { f, _ in f })
                self.monitor.deviceNames = self.deviceNames
                self.rebuildDeviceMenu(selected: saved)
            }
        }
    }

    @objc private func setGracePeriod(_ sender: NSMenuItem) {
        Settings.gracePeriod = TimeInterval(sender.tag)
        restartMonitor()
    }

    @objc private func setThreshold(_ sender: NSMenuItem) {
        Settings.rssiThreshold = sender.tag
        restartMonitor()
    }

    @objc private func setLockMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = LockMode(rawValue: raw) else { return }
        Settings.lockMode = mode
        restartMonitor()
    }

    @objc private func toggleLaunchAtLogin() {
        if loginManager.isEnabled {
            loginManager.disable()
        } else {
            try? loginManager.enable(executablePath: ProcessInfo.processInfo.arguments[0])
        }
        syncLaunchAtLoginItem()
    }

    @objc private func toggleMonitoring() {
        isEnabled.toggle()
        if isEnabled {
            monitor.start()
            toggleMenuItem.title = L("menu.disable_monitoring")
        } else {
            monitor.stop()
            toggleMenuItem.title = L("menu.enable_monitoring")
            statusMenuItem.title = L("status.monitoring_disabled")
        }
    }

    @objc private func lockNow() { ScreenLocker.lock() }
}
