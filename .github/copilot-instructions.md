# Copilot Context Guide: MacStats

Purpose: A tiny macOS menu bar utility that shows current CPU and Memory usage with minimal overhead and optional detail popover.

## Core Goals
- Always-visible, glanceable CPU and Memory data in menu bar
- Accurate + stable values (aligned with Activity Monitor for memory %)
- Lightweight (low CPU usage, minimal allocations, tiny binary)
- Intuitive: left click = detail + settings, right click = quick menu
- Zero feature bloat: focus strictly on CPU + Memory

## Non-Goals
- No per-process breakdowns
- No GPU / network / disk metrics
- No historical charts / logging
- No complex windowing, just status item + popover

## Architecture Overview
- `MacStatsApp.swift`: App entry, sets up controller singletons
- `MenuBarController.swift`: Owns `NSStatusItem`, SwiftUI popover, formatting, Activity Monitor integration (AppleScript launch helpers)
- `SystemMonitor.swift`: Sampling logic for CPU + Memory
  - CPU via `host_processor_info` diff between ticks (user, system, idle)
  - Memory via `vm_statistics64` building an App Memory style usage
- `UserPreferences.swift`: `UserPreferencesManager` singleton, `@Published` properties persisted in `UserDefaults` (display format, refresh interval, theme)
- `ContentView.swift`: SwiftUI view composition used inside the popover

## Key Data Types
- `DisplayFormat` enum: `.compact`, `.detailed`, `.cpuOnly`, `.memoryOnly`
- `RefreshInterval` enum (Double rawValue seconds): `.oneSecond = 1`, `.twoSeconds = 2`, `.fiveSeconds = 5`, `.tenSeconds = 10`

## Update Loop
1. A timer / dispatch source triggers at chosen refresh interval
2. `SystemMonitor` samples raw CPU ticks + memory stats
3. CPU % computed by delta ticks vs total ticks
4. Memory % = (usedAppMemoryBytes / totalPhysicalBytes)
5. `MenuBarController` formats according to `DisplayFormat`
6. Status item title updated on main thread

## Activity Monitor Integration
- Clicking CPU text -> `openActivityMonitorCPU()` (AppleScript opens & selects CPU tab)
- Clicking Memory text -> `openActivityMonitorMemory()` ( selects Memory tab )
- Implemented as static helpers to keep SwiftUI gesture closures simple

## Styling / UX Principles
- Keep title under ~30 characters for compact mode
- Avoid frequent string allocations; reuse formatters if introduced
- Avoid blocking main thread in sampling or formatting

## Performance Considerations
- Do not sample more often than 1s
- Reuse previous CPU snapshot to compute delta; never reset unexpectedly
- Avoid enumerating processes

## Extension Points (If Needed Later)
- Add optional temperature sensor (behind feature flag)
- Add minimal notification when memory crosses threshold

## Implementation Guidelines for Future Changes
- Prefer small pure helper functions in `SystemMonitor` for new metrics
- Never add third-party dependencies for trivial formatting
- Keep enums exhaustive with switch statements to catch new cases
- Validate memory logic remains aligned with Activity Monitor after macOS updates

## Testing Ideas (Manual)
- Compare values to Activity Monitor over several load scenarios
- Stress test by setting 1s refresh and running CPU-heavy tasks
- Validate Activity Monitor tab switching works when already open & when closed

## Common Pitfalls
- Forgetting to diff CPU ticks -> shows near 0% or spikes
- Including free/inactive memory incorrectly -> wrong % compared to Activity Monitor
- Updating UI off main thread -> warnings / flicker

## Suggested Copilot Behaviors
- When asked for a new metric: remind of non-goals and confirm alignment
- Encourage minimalism and energy efficiency
- Offer enum-based approach over raw strings for new user-facing modes

## License
MIT – contributions should keep code lean and focused.
