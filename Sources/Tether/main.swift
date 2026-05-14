import Cocoa
import Darwin

// Single-instance guard via flock on a lock file.
// flock is released automatically when the process exits.
let lockPath = "/tmp/tether.lock"
let lockFd = open(lockPath, O_CREAT | O_RDWR, 0o644)
guard lockFd >= 0, flock(lockFd, LOCK_EX | LOCK_NB) == 0 else {
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
