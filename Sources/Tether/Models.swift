import Foundation

struct BTDevice {
    let name: String
    let address: String
}

enum LockMode: String {
    case anyDeviceLeaves  // 單一裝置離開就鎖
    case allDevicesLeave  // 所有裝置都離開才鎖
}
