# Codex Usage Menubar

Minimal macOS menu bar app for Codex usage.

## Screenshots

<p>
  <img src="assets/codex-usage-healthy.png" alt="Codex Usage Menubar with healthy availability" width="49%">
  <img src="assets/codex-usage-warning-critical.png" alt="Codex Usage Menubar with low and critical availability" width="49%">
</p>

## Quickstart

Use this if you want to run the current source locally.

```bash
git clone https://github.com/lasseveenliese/codex-usage-menubar.git
cd codex-usage-menubar
./start.command
```

The app reads the newest Codex session logs from `~/.codex` by default.
Set `CODEX_HOME` before launching if your data lives elsewhere.
To simulate values at launch, set `CODEX_USAGE_MENUBAR_SIMULATE_PRIMARY_USED_PERCENT` and `CODEX_USAGE_MENUBAR_SIMULATE_SECONDARY_USED_PERCENT`.
The app only reads local Codex data and does not send usage information to external services.
It checks GitHub periodically for app updates, but that request does not include Codex usage data.

`start.command` rebuilds the app and keeps only one instance running.

## Download

Use this if you want the packaged app without cloning the repository.

[CodexUsageMenubar.dmg](https://github.com/lasseveenliese/codex-usage-menubar/releases/download/latest/CodexUsageMenubar.dmg)

Open the DMG, drag `Codex Usage Menubar.app` into `Applications`, then open it from there.

⚠️ The download is not notarized by Apple yet, so macOS may warn on first open.
If you trust it, right-click the app in `Applications` and choose `Open`, or use `System Settings > Privacy & Security > Open Anyway`.

## Notes

- Updates once per minute.
- Checks for app updates on launch and at most every 12 hours.
- Falls back to `Codex -- | weekly --` if no Codex data is found.
