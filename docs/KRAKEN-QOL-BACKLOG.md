# Kraken QoL backlog

This is the product backlog for quality-of-life improvements that should shape Kraken's launcher experience. Some items are intentionally not implemented yet. Treat them as planned work, not working features.

## Library
- Remember the user's preferred grid/list layout.
- Remember per-window card sizing and sensible defaults.
- Sort by recently played, title, installed, storefront, favourite, and update available.
- Add a compact filter bar with removable filter chips.
- Add a "Recently added" section.
- Add a "Needs attention" section for updates, repair failures, or missing environments.
- Multi-select games for batch actions.
- Batch update, verify, move, uninstall, favourite, and delete metadata.
- Drag and drop to reorder favourites.
- Hide games without deleting them from disk.
- Pin games to the top of the library.
- Show installation size and free-space impact before large operations.
- Preserve scroll position when returning from game settings.
- Search titles, executable names, launch arguments, and metadata.
- Keyboard shortcuts for search, play, favourite, settings, and layout switching.
- Context menus with the same actions as the visible game controls.
- Remember the last selected game across launches.

## Game page and launching
- One obvious primary Play button.
- Show a clear launch status: preparing, starting, running, stopped, failed.
- Detect an already-running game and offer to focus it instead of launching twice.
- "Stop game" and "Force stop" with clear escalation.
- Optional automatic minimisation of Kraken while a game runs.
- Optional restore of Kraken when the game exits.
- Per-game launch presets.
- Per-game launch argument history.
- Safe argument templates with plain-English explanations.
- Game-specific compatibility notes and troubleshooting hints.
- One-click "Repair environment" flow.
- One-click "Open game folder" and "Open prefix" actions.
- Copy diagnostic information without exposing unrelated private data.
- Remember the last successful compatibility setup.
- Offer a rollback to the previous working compatibility setup.

## Compatibility and runtimes
- Automatic runtime selection based on validated compatibility information.
- Manual runtime override only when explicitly enabled.
- Runtime health checks before launch.
- Container/runtime mismatch detection before starting a process.
- Explain exactly why a runtime cannot be used.
- Runtime recommendation history per game.
- Fast toggle between known-good per-game profiles.
- Automatic fallback after a failed launch, with user confirmation.
- Runtime download, repair, verify, and remove flows that never touch another runtime.
- Show runtime version and architecture only in Advanced/diagnostic UI.

## Installation and operations
- Install queue with pause, resume, cancel, retry, and reorder.
- Per-operation speed, progress, remaining time, and disk usage.
- Queue persistence across application restarts.
- Retry failed operations without starting from zero when safe.
- Preflight checks for disk space and writable locations.
- Clear distinction between download, extraction, verification, and finalisation.
- Notification when a long operation finishes.
- Prevent accidental concurrent writes to the same game/container.
- Safe recovery after interruption or force quit.

## Containers
- Friendly names plus compact runtime badges.
- Show which games use a container before deleting it.
- Warn about disk space and dependent games before removal.
- Duplicate/copy a container for experimentation.
- Rename containers without breaking references.
- Health check and repair action.
- Show container size.
- Show runtime/version details only in Advanced UI.

## Performance, thermals, and battery
- Lightweight performance HUD that can be enabled per game.
- Optional FPS, frame-time, CPU, GPU, memory, and temperature display.
- Detect sustained thermal pressure and surface a non-intrusive warning.
- Battery-aware launch mode for MacBook users.
- Optional low-power mode that reduces background Kraken activity while a game runs.
- Avoid unnecessary polling when the library is idle.
- Lazy-load heavy artwork and metadata.
- Cache artwork with bounded disk usage and cleanup controls.
- Pause nonessential background refresh while a game is running.
- Diagnostics for stutter/frame-pacing issues.

## Reliability and recovery
- Crash-safe operation journal.
- Startup recovery for interrupted operations.
- Automatic detection of stale lock files/process state.
- Clear error messages with a human explanation first and technical detail behind Advanced.
- Copyable error reports.
- Optional automatic log collection after a failed launch.
- "Try again" that actually resets only the failed step.
- Health dashboard for Kraken, runtimes, containers, and game installations.

## Accessibility and usability
- Full keyboard navigation.
- Consistent focus rings and shortcut hints.
- Larger text support.
- Better VoiceOver labels for game actions and status indicators.
- Reduced-motion support.
- High-contrast-friendly controls.
- Plain-English descriptions for technical settings.
- No destructive action without a clear confirmation when recovery is difficult.

## Personalisation
- Light/dark/system appearance support where appropriate.
- Optional compact density mode.
- Library grouping by genre/storefront/platform when metadata supports it.
- Custom favourite sections.
- Optional game artwork overrides.
- Optional background artwork on the game detail page.
- Remember window size, sidebar width, and last location.

## Future integrations
- Steam account integration improvements.
- Better Epic account state handling.
- Import metadata from installed games without requiring a storefront login.
- Controller detection and per-game controller hints.
- Cloud-save status where a storefront exposes it safely.
- Compatibility database integration with cached offline results.

## Implementation rule
Items in this document are planning targets. A feature must not be described in the UI as working until its underlying implementation has been verified. Prefer keeping unfinished ideas hidden or clearly labelled during development rather than creating controls that imply functionality we do not yet have.
