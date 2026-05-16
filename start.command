#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_ROOT="$ROOT_DIR/.build/codex-usage-menubar"
APP_PATH="$BUILD_ROOT/Codex Usage Menubar.app"
MACOS_DIR="$APP_PATH/Contents/MacOS"
RESOURCES_DIR="$APP_PATH/Contents/Resources"
MODULE_CACHE="/private/tmp/codex-usage-menubar-module-cache"
ICON_SOURCE="$ROOT_DIR/assets/app-icon-source.png"
ICON_FILE="$RESOURCES_DIR/AppIcon.icns"
SIMULATION_ARGS=()

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$MODULE_CACHE"

PRIMARY_SIMULATION="${CODEX_USAGE_MENUBAR_SIMULATE_PRIMARY_USED_PERCENT:-${CODEX_LIMITBAR_SIMULATE_PRIMARY_USED_PERCENT:-}}"
if [[ -n "$PRIMARY_SIMULATION" ]]; then
  SIMULATION_ARGS+=(--simulate-primary-used-percent "$PRIMARY_SIMULATION")
fi

SECONDARY_SIMULATION="${CODEX_USAGE_MENUBAR_SIMULATE_SECONDARY_USED_PERCENT:-${CODEX_LIMITBAR_SIMULATE_SECONDARY_USED_PERCENT:-}}"
if [[ -n "$SECONDARY_SIMULATION" ]]; then
  SIMULATION_ARGS+=(--simulate-secondary-used-percent "$SECONDARY_SIMULATION")
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

build_app_icon() {
  if [[ ! -f "$ICON_SOURCE" ]]; then
    echo "Missing app icon source: $ICON_SOURCE" >&2
    exit 1
  fi

  cat <<'SWIFT' | swift - "$ICON_SOURCE" "$ICON_FILE"
import AppKit

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
let source = NSImage(contentsOf: sourceURL)!
let sizes = [128, 256, 512, 1024]
let fileManager = FileManager.default

try? fileManager.removeItem(at: outputURL)

func renderPNG(size: Int) -> Data {
  let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size,
    pixelsHigh: size,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
  )!
  rep.size = NSSize(width: size, height: size)

  guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
    fatalError("Could not create bitmap context")
  }

  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = context
  context.imageInterpolation = .high
  NSColor.clear.setFill()
  NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size)).fill()
  source.draw(
    in: NSRect(x: 0, y: 0, width: size, height: size),
    from: .zero,
    operation: .copy,
    fraction: 1
  )
  NSGraphicsContext.restoreGraphicsState()

  return rep.representation(using: .png, properties: [:])!
}

func chunk(type: String, data: Data) -> Data {
  var chunk = Data(type.utf8)
  var length = UInt32(data.count + 8).bigEndian
  withUnsafeBytes(of: &length) { chunk.append(contentsOf: $0) }
  chunk.append(data)
  return chunk
}

var payload = Data()
for size in sizes {
  let png = renderPNG(size: size)
  let type: String
  switch size {
  case 128: type = "ic07"
  case 256: type = "ic08"
  case 512: type = "ic09"
  case 1024: type = "ic10"
  default: fatalError("Unsupported icon size")
  }
  payload.append(chunk(type: type, data: png))
}

var file = Data("icns".utf8)
var totalLength = UInt32(payload.count + 8).bigEndian
withUnsafeBytes(of: &totalLength) { file.append(contentsOf: $0) }
file.append(payload)
try file.write(to: outputURL)
SWIFT
}

sign_app_bundle() {
  xattr -d com.apple.FinderInfo "$APP_PATH" 2>/dev/null || true
  xattr -d com.apple.fileprovider.fpfs#P "$APP_PATH" 2>/dev/null || true
  xattr -d com.apple.provenance "$APP_PATH" 2>/dev/null || true
  codesign --force --deep --sign - "$APP_PATH" >/dev/null
  xattr -d com.apple.FinderInfo "$APP_PATH" 2>/dev/null || true
  xattr -d com.apple.fileprovider.fpfs#P "$APP_PATH" 2>/dev/null || true
  xattr -d com.apple.provenance "$APP_PATH" 2>/dev/null || true
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
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
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

build_app_icon

swiftc \
  -module-cache-path "$MODULE_CACHE" \
  "$ROOT_DIR"/Sources/CodexUsageMenubar/*.swift \
  -framework AppKit \
  -o "$MACOS_DIR/CodexUsageMenubar"

sign_app_bundle

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
