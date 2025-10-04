# MacStats 📊

Lightweight macOS menu bar app showing real‑time CPU, Memory, and Disk usage. Built to be simple, accurate, and low overhead.

![MacStats Demo](assets/demo.gif)

## Why
You shouldn’t need a heavy multi‑window monitor just to glance at CPU and memory. MacStats gives you the essentials in the menu bar with optional detail on click.

## Key Features

* Live CPU %, Memory %, and Disk % (main volume) with color thresholds (disk ≥80% amber, ≥90% red) and matching SF Symbol icons in the menu bar
* Two display formats (Compact, Detailed) — both can include any enabled metrics
* Click CPU or Memory text to open Activity Monitor on the corresponding tab
* Configurable refresh interval (1s / 2s / 5s / 10s)
* Accurate memory calculation aligned with Activity Monitor (App Memory perspective)
* SwiftUI native UI, minimal footprint, universal binary (Apple Silicon + Intel)

## Quick Start

```bash
git clone https://github.com/yourusername/mac-stats.git
cd mac-stats
make run   # or: make dev
```

The status item appears in the menu bar. Left‑click for the popover (detailed view + settings). Right‑click for quick format / refresh changes.

## Install (Binary)
 
1. Download the latest release (DMG or ZIP)
2. Move `MacStats.app` to Applications
3. Launch (Spotlight or Applications)

## Display Formats

Compact keeps things tight (integer percentages). Detailed shows one decimal for CPU plus used/total for memory and disk.

## Settings Persist
 
Automatically stored via `UserDefaults`: display format, refresh interval, theme preference.

## Activity Monitor Integration
 
* Click CPU label → Opens Activity Monitor on CPU tab
* Click Memory label → Opens Activity Monitor on Memory tab
If Activity Monitor isn’t running it will be launched automatically.

## Requirements
 
macOS 13.0+, Xcode 15+ (to build).

## Build From Source

```bash
make build     # release artifacts
make dev       # fast debug build
open MacStats.xcodeproj # build/run inside Xcode (⌘+R)
```

Artifacts (release): unsigned .app, optional zip / dmg (if create-dmg installed).

defaults delete com.macstats.app || true
## Uninstall


 
Quit the app, then remove:

```bash
rm -rf /Applications/MacStats.app
defaults delete com.macstats.app || true
```

## Project Structure

```text
MacStats/
  MacStats/                  Core sources
    SystemMonitor.swift      CPU + Memory + Disk collection
    MenuBarController.swift  Status item + popover + formatting + Activity Monitor hooks
    UserPreferences.swift    Persistence (UserDefaults)
    ContentView.swift        SwiftUI views
    MacStatsApp.swift        Entry point
```

## Technical Notes

CPU: Derived via `host_processor_info` diffing ticks between samples.  
Memory: App memory (active + wired + compressed) vs total physical for Activity Monitor alignment.  
Disk: Main volume used = total − free (FileManager attributes) with % + thresholds (80/90%).  
Refresh: Timer driven (DispatchSource / Combine) using selected interval.  
UI: SwiftUI embedded in `NSStatusItem` with a popover.

## Goals

* Stay tiny (< a few MB, negligible runtime CPU)
* Zero external heavy dependencies
* Fast sample + format + paint cycle
* Clear, glanceable text first; extra detail optional

## Non‑Goals

* Process-level breakdowns
* GPU metrics
* Network or disk IO panels (only a single aggregate disk % is shown)

## Contributing

Small focused PRs welcome (bugfixes, accuracy improvements, energy efficiency). Avoid feature creep that bloats memory/CPU.

## License

MIT. See [LICENSE](LICENSE).

---
Made with ❤️ to keep your Mac calm.
