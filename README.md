# Tether

A macOS menu bar utility that automatically locks your screen when a paired Bluetooth device moves out of range.

## Requirements

- macOS 13 Ventura or later
- Swift 5.9+ (only needed if building from source)

## Installation

### Build from source

```bash
git clone https://github.com/happy-llama/Tether.git
cd Tether
make install          # builds and copies to /Applications
```

Or just build without installing:

```bash
make app              # produces Tether.app in the project directory
```

### First launch

Because the app is not notarized, macOS Gatekeeper will block it on first open.
Right-click `Tether.app` → **Open** → **Open** to allow it.

## How It Works

Tether polls your Mac's Bluetooth stack every 8 seconds and reads the RSSI (signal strength) of each watched device. A device must be detected at least once before it counts as a criterion — devices you didn't bring that day are ignored. A device is only considered gone after **two consecutive missed polls**, then the grace period countdown begins. When it expires, the screen is locked via `pmset displaysleepnow`.

After a lock, the active device set resets. Only devices that return after you unlock the screen are re-admitted as criteria — devices that stay away are automatically excluded until they reappear.

No third-party tools required. Everything runs on built-in macOS utilities.

## Settings

All settings are accessible from the menu bar icon.

| Setting | Options | Default |
|---|---|---|
| **Watched Devices** | Any paired Bluetooth device | *(none)* |
| **Lock Delay** | 10 s / 30 s / 60 s | 30 s |
| **Sensitivity** | ~1 m / ~3 m / ~5 m / ~10 m | ~5 m |
| **Lock Condition** | All devices leave / Any device leaves | All leave |
| **Launch at Login** | On / Off | Off |

**Lock Condition** controls multi-device behaviour:
- *All devices leave* — locks only when every watched device is out of range (good if you carry multiple devices).
- *Any device leaves* — locks as soon as one device goes out of range (stricter).

## Known Limitations

- **~16-second detection lag** — a device must miss two consecutive polls (2 × 8 s) before the grace period starts. Total time from leaving to lock is roughly 16 s + grace period.
- **RSSI is approximate** — signal strength is affected by walls, body position, and RF interference. The distance labels are estimates.
- **Moving the app breaks Launch at Login** — the LaunchAgent stores the executable path at the time you enable the setting. If you move `Tether.app`, disable and re-enable *Launch at Login*.
- **Not notarized** — Gatekeeper will prompt on first launch (see [First launch](#first-launch)).

## License

MIT
