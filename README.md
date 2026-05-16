# Codex Limit Bar

Tiny macOS menu bar app that shows your Codex 5-hour and weekly usage as:

`5h x% | weekly x%`

## Start

Double-click `start.command`, or run:

```bash
./start.command
```

The app reads the newest Codex session logs from `~/.codex` by default.
If needed, set `CODEX_HOME` before launching.
The terminal stays attached while the app runs.

## Simulate values

To test the UI with manual values, set these environment variables before launch:

```bash
CODEX_LIMITBAR_SIMULATE_PRIMARY_USED_PERCENT=82 \
CODEX_LIMITBAR_SIMULATE_SECONDARY_USED_PERCENT=18 \
./start.command
```

Optional reset timestamps:

- `CODEX_LIMITBAR_SIMULATE_PRIMARY_RESETS_AT`
- `CODEX_LIMITBAR_SIMULATE_SECONDARY_RESETS_AT`

Use Unix seconds or ISO-8601, for example `2026-05-16T03:12:00Z`.

These values are the percentages you want to see in the UI, not the raw Codex `used_percent` values.
So `18` and `9` mean the bar should show `18%` and `9%` remaining.

The launcher forwards these values into the app process, so this works even though the app is opened via `open`.

For a ready-made mixed color demo with yellow and red at the same time:

```bash
CODEX_LIMITBAR_SIMULATE_PRESET=warning-critical ./start.command
```

This shows `5h` in yellow/orange and `7d` in red.

## Test

1. Start the app.
2. Look for the `Launching CodexLimitBar` line and confirm no error appears.
3. Wait for the menu bar item to appear.
4. Run a Codex task and refresh after a minute.
5. Confirm the title updates to the current percentages.

## Notes

- The app updates once per minute.
- If no Codex data is found yet, it falls back to `Codex -- | weekly --`.
