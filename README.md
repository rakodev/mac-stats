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

## Installation

### Homebrew (Recommended)

```bash
brew tap rakodev/tap
brew install --cask macstats
```

Or in one command:

```bash
brew install --cask rakodev/tap/macstats
```

### Direct Download

Download the latest release from [GitHub Releases](https://github.com/rakodev/mac-stats/releases):

1. Download `MacStats-Installer.dmg` (or `MacStats.zip`)
2. Open the DMG and drag MacStats to Applications
3. Launch MacStats from Applications or Spotlight

## Quick Start

The status item appears in the menu bar. Left‑click for the popover (detailed view + settings). Right‑click for quick format / refresh changes.

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
git clone https://github.com/rakodev/mac-stats.git
cd mac-stats
make run       # build and run (development)
make build     # release build (signed)
make release   # full release: build, sign, notarize, GitHub release, Homebrew update
```

See [DISTRIBUTION.md](DISTRIBUTION.md) for signing and notarization setup.

## Update

### Homebrew

```bash
brew update
brew upgrade --cask macstats
```

### Direct Download

Download the latest version from [GitHub Releases](https://github.com/rakodev/mac-stats/releases) and replace the app in your Applications folder.

## Uninstall

If installed via Homebrew:

```bash
brew uninstall --cask macstats
```

If installed manually, quit the app and run:

```bash
rm -rf /Applications/MacStats.app
defaults delete com.macstats.app 2>/dev/null || true
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
