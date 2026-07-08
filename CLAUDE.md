# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

MacStats is a lightweight macOS menu bar app that shows real-time CPU, Memory, aggregate Disk usage (main volume `/`), and optional CPU temperature. It is a menu bar only app (no dock icon by default, `.accessory` activation policy) built with SwiftUI + AppKit. The design priority is minimal overhead: small binary, low CPU, few allocations, and values that stay aligned with Activity Monitor where Activity Monitor exposes comparable metrics.

Bundle id: `com.macstats.app`. Requires macOS 13.0+ and Xcode 15+ to build. Universal binary (Apple Silicon + Intel). No third-party dependencies.

## Commands

```bash
make dev      # Debug build via xcodebuild (dev-build.sh)
make run      # clean + dev build, then launch the app from DerivedData (run.sh)
make build    # Release build, sign, notarize, staple, produce ZIP/DMG (build.sh)
make release  # Full release: version bump, git tag, GitHub release, Homebrew tap (build.sh release)
make clean    # Remove build/, DerivedData, kill running MacStats process
```

There is no automated test target. Verification is manual: build, launch, and compare values against Activity Monitor (see Verification below).

To iterate quickly on code, `make run` rebuilds and relaunches. `run.sh` finds the built `.app` under `~/Library/Developer/Xcode/DerivedData` and `open`s it, killing any existing MacStats process first.

## Architecture

All source is in `MacStats/`. The flow is: `SystemMonitor` samples raw metrics on a timer, publishes a `SystemStats` struct, and `MenuBarController` observes it and drives a custom `NSView` in the status item plus a SwiftUI popover.

- **`MacStatsApp.swift`** - `@main` entry. Uses an empty hidden `WindowGroup` and an `AppDelegate` that sets `.accessory` activation policy, closes stray windows, and instantiates the single `MenuBarController`. On version change or first launch it re-enables launch at login via `SMAppService`.
- **`SystemMonitor.swift`** - Sampling. `ObservableObject` publishing `currentStats: SystemStats`. A `Timer` fires at the refresh interval; sampling runs on a background queue and results are pushed back on the main queue.
  - CPU: `host_processor_info(PROCESSOR_CPU_LOAD_INFO)`, aggregated across cores, computed as a delta of ticks (user + system + nice) over total ticks vs the previous sample. First sample reads 0 (no previous snapshot).
  - Memory: `host_statistics64(HOST_VM_INFO64)`. "App Memory" style = (active + wired + compressed) pages x page size, over `physicalMemory`. Inactive, free, and speculative are deliberately excluded to match Activity Monitor's App Memory.
  - Disk: `FileManager.attributesOfFileSystem(forPath: "/")`, used = total - free. Root volume only.
  - Temperature: `TemperatureReader` uses Apple Silicon IOHID PMU die sensors first, returning the hottest `PMU tdie*` reading as CPU Die. Falls back to `SMCTemperatureReader` on Intel, preferring CPU proximity (`TC0P`). Returns `nil` when no compatible sensor is available.
- **`MenuBarController.swift`** - Owns the `NSStatusItem`, the `StatusItemView`, and the SwiftUI popover (`MenuBarPopoverView`). Observes `SystemMonitor.$currentStats` and `UserPreferencesManager` publishers via Combine. Left click toggles the popover; right click shows a context menu (Settings placeholder + Quit). Also holds the static AppleScript helpers for Activity Monitor.
- **`StatusItemView.swift`** - Custom `NSView` that draws the menu bar content directly (icons + values) rather than using a status item title string. Two `LayoutStyle`s: `.horizontal` (SF Symbol icon beside value) and `.vertical` (short label CPU/MEM/SSD/TMP above value). Positions are fixed pixel offsets to prevent jitter. Icons are template images cached per metric kind and regenerated on appearance (light/dark) change.
- **`UserPreferences.swift`** - `UserPreferencesManager.shared`, an `ObservableObject` whose `@Published` properties persist to `UserDefaults` in `didSet`. Also contains `TemperatureUnit`, `ThemeManager` (light/dark/system via `NSApp.appearance`), and the `Theme` enum.
- **`ContentView.swift`** - Minimal placeholder view (the app is menu bar only, so this is rarely shown).

### Key types

- `DisplayFormat` (in `MenuBarController.swift`): `.compact` and `.vertical` only. Default is `.vertical`. (Note: `.github/copilot-instructions.md` and `CHANGELOG.md` mention older `.detailed`/`.cpuOnly`/`.memoryOnly` cases that no longer exist.)
- `RefreshInterval` (Double seconds): `.oneSecond`, `.twoSeconds` (default), `.fiveSeconds`, `.tenSeconds`.
- `TemperatureUnit`: `.celsius` (default) and `.fahrenheit`. Sampling remains Celsius; conversion happens at display formatting.
- Metric visibility is independent of format via `showCPU` / `showMemory` / `showDisk` / `showTemperature` prefs. At least one must stay enabled (`showLastMetricWarning` blocks disabling the last one). Temperature defaults off to preserve menu bar width and because thermal sensor availability varies by Mac model.

### Preferences wiring

Preferences are stored in two places that are kept in sync: `UserPreferencesManager` is the persisted source of truth, and `MenuBarController` mirrors `displayFormat`/`refreshInterval` into its own `@Published` props for SwiftUI bindings. When changing a preference from the popover, update both the controller and the manager, then call the relevant update method (see how `MenuBarPopoverView` pickers do it). Changing metric visibility recreates the status item; changing format resizes it. Width is based on visible metric count (vertical = 30pt per metric, horizontal = 48pt per metric plus 6pt padding).

## Activity Monitor integration

Clicking CPU / Memory / Disk in the popover runs an `NSAppleScript` that activates Activity Monitor and selects the matching tab (`openActivityMonitorCPU/Memory/Disk`, static on `MenuBarController`). This needs the Automation permission and works whether or not Activity Monitor is already open. The app is not sandboxed (`MacStats.entitlements` sets `app-sandbox` false), which AppleScript control and filesystem stats depend on.

## Product scope (goals and non-goals)

Keep the feature set minimal. In scope: CPU %, Memory %, single-volume Disk %, optional CPU temperature in the menu bar, plus an optional detail popover and lightweight settings.

Out of scope (do not add without a strong, validated reason): per-process breakdowns, GPU or network metrics, disk IO or per-volume panels, historical charts or logging, extra windows. When asked for broader metrics, confirm alignment with this minimal scope first.

## Performance and correctness constraints

- Do not sample more often than 1s.
- Keep sampling and formatting off the main thread; only update UI on the main thread.
- Never reset the previous CPU snapshot unexpectedly; the delta depends on it (skipping the diff shows ~0% or spikes).
- Do not enumerate processes. One filesystem attribute fetch per interval, root volume only.
- Temperature is best-effort via IOHID on Apple Silicon and private AppleSMC keys on Intel. Keep it optional, tolerate `nil`, and do not require privileged tools like `powermetrics`.
- Keep memory logic as App Memory (active + wired + compressed); mixing in free/inactive/speculative breaks alignment with Activity Monitor. Re-validate after macOS updates.
- Prefer small pure helpers in `SystemMonitor` for new metrics. Keep enums exhaustive with switch statements. No third-party deps for trivial formatting. Watch menu bar width impact before adding text.

## Verification (manual)

Typical checks after a change: `make dev` / `make build` succeed; the status item shows enabled metrics and updates; settings persist across relaunch; Activity Monitor tab switching works both when it is open and closed; values track Activity Monitor under load where comparable (stress test at 1s refresh with a CPU-heavy task). For temperature, verify the popover either shows a CPU sensor value or a stable Unavailable state.

## Release and distribution

`build.sh` signs with a Developer ID cert and notarizes using the `MacClipboard-Notarize` keychain profile (shared with a sibling app). `make release` also bumps `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` in `project.pbxproj`, tags, pushes, creates a GitHub release, and updates the Homebrew cask in `rakodev/homebrew-tap`. See `DISTRIBUTION.md` for signing/notarization setup and troubleshooting.

## Task tracking

Track product and engineering work in `docs/`:

- `docs/BACKLOG.md` - committed, actionable tasks (priority P0/P1/P2, evidence, acceptance criteria, verification).
- `docs/FOLLOWUPS.md` - lower-confidence ideas not yet ready for the backlog.
- `docs/BACKLOG_ARCHIVE.md` - completed tasks with date, summary, and verification used.

Workflow: add actionable issues found during work to `BACKLOG.md`, softer ideas to `FOLLOWUPS.md`, and move items to `BACKLOG_ARCHIVE.md` when done. Keep items concrete (affected area, why it matters, what done means, how to verify).
