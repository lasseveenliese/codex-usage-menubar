# Codex Usage Menubar

Minimal macOS menu bar app for Codex usage.

## Screenshots

![Codex Usage Menubar with low and critical availability](assets/codex-usage-warning-critical.png)

![Codex Usage Menubar with healthy availability](assets/codex-usage-healthy.png)

## Start

```bash
./start.command
```

The app reads the newest Codex session logs from `~/.codex` by default.
Set `CODEX_HOME` before launching if your data lives elsewhere.
To simulate values at launch, set `CODEX_LIMITBAR_SIMULATE_PRIMARY_USED_PERCENT` and `CODEX_LIMITBAR_SIMULATE_SECONDARY_USED_PERCENT`.

`start.command` rebuilds the app and keeps only one instance running.

## Notes

- Updates once per minute.
- Falls back to `Codex -- | weekly --` if no Codex data is found.
