import Foundation

struct Settings {
    private static let defaults = UserDefaults.standard

    static var gracePeriod: TimeInterval {
        get { TimeInterval(defaults.integer(forKey: "gracePeriod").nonZeroOr(30)) }
        set { defaults.set(Int(newValue), forKey: "gracePeriod") }
    }

    static var rssiThreshold: Int {
        get { defaults.integer(forKey: "rssiThreshold").nonZeroOr(-70) }
        set { defaults.set(newValue, forKey: "rssiThreshold") }
    }

    static var lockMode: LockMode {
        get {
            let raw = defaults.string(forKey: "lockMode") ?? ""
            return LockMode(rawValue: raw) ?? .allDevicesLeave
        }
        set { defaults.set(newValue.rawValue, forKey: "lockMode") }
    }

    static var selectedAddresses: [String] {
        get { defaults.stringArray(forKey: "selectedAddresses") ?? [] }
        set { defaults.set(newValue, forKey: "selectedAddresses") }
    }
}

extension Int {
    func nonZeroOr(_ fallback: Int) -> Int { self == 0 ? fallback : self }
}
