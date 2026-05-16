#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_ROOT="$ROOT_DIR/.build/codex-usage-menubar"
APP_PATH="$BUILD_ROOT/Codex Usage Menubar.app"
MACOS_DIR="$APP_PATH/Contents/MacOS"
MODULE_CACHE="/private/tmp/codex-usage-menubar-module-cache"
SIMULATION_ARGS=()

mkdir -p "$MACOS_DIR" "$MODULE_CACHE"

if [[ -n "${CODEX_LIMITBAR_SIMULATE_PRIMARY_USED_PERCENT:-}" ]]; then
  SIMULATION_ARGS+=(--simulate-primary-used-percent "$CODEX_LIMITBAR_SIMULATE_PRIMARY_USED_PERCENT")
fi

if [[ -n "${CODEX_LIMITBAR_SIMULATE_SECONDARY_USED_PERCENT:-}" ]]; then
  SIMULATION_ARGS+=(--simulate-secondary-used-percent "$CODEX_LIMITBAR_SIMULATE_SECONDARY_USED_PERCENT")
fi

terminate_existing_app() {
  pkill -x CodexUsageMenubar 2>/dev/null || true

  for _ in {1..20}; do
    if ! pgrep -x CodexUsageMenubar >/dev/null 2>&1; then
      return
    fi

    sleep 0.1
  done
}

cat > "$APP_PATH/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>CodexUsageMenubar</string>
  <key>CFBundleIdentifier</key>
  <string>local.codex.usagemenubar</string>
  <key>CFBundleName</key>
  <string>Codex Usage Menubar</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

swiftc \
  -module-cache-path "$MODULE_CACHE" \
  "$ROOT_DIR"/Sources/CodexUsageMenubar/*.swift \
  -framework AppKit \
  -o "$MACOS_DIR/CodexUsageMenubar"

if [[ "${BUILD_ONLY:-0}" == "1" ]]; then
  exit 0
fi

echo "Launching Codex Usage Menubar"
terminate_existing_app
if (( ${#SIMULATION_ARGS[@]} > 0 )); then
  open -n "$APP_PATH" --args "${SIMULATION_ARGS[@]}"
else
  open -n "$APP_PATH"
fi
