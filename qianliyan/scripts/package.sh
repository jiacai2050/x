#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "==> 1. Building Zig core (ReleaseFast)..."
cd "${ROOT_DIR}"
zig build -Doptimize=ReleaseFast "$@"

echo "==> 2. Building Swift application (release)..."
cd "${ROOT_DIR}/macos"
swift build -c release

echo "==> 3. Assembling Qianliyan.app bundle..."
DIST_DIR="${ROOT_DIR}/dist"
APP_DIR="${DIST_DIR}/Qianliyan.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp "${ROOT_DIR}/macos/.build/release/Qianliyan" "${MACOS_DIR}/Qianliyan"
chmod +x "${MACOS_DIR}/Qianliyan"

if [ ! -f "${ROOT_DIR}/resources/AppIcon.icns" ]; then
    echo "==> Generating AppIcon.icns..."
    swift "${ROOT_DIR}/scripts/generate_icon.swift"
fi
cp "${ROOT_DIR}/resources/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"

cat << 'EOF' > "${CONTENTS_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Qianliyan</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.jiacai.qianliyan</string>
    <key>CFBundleName</key>
    <string>Qianliyan</string>
    <key>CFBundleDisplayName</key>
    <string>Qianliyan</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
</dict>
</plist>
EOF

echo "==> 4. Signing app with Ad-hoc signature..."
xattr -cr "${APP_DIR}"
codesign --force --deep -s - "${APP_DIR}"

echo "==> 5. Creating DMG distribution archive..."
STAGING_DIR="${DIST_DIR}/dmg_staging"
rm -rf "${STAGING_DIR}" "${DIST_DIR}/Qianliyan.dmg"
mkdir -p "${STAGING_DIR}"

cp -R "${APP_DIR}" "${STAGING_DIR}/"
ln -s /Applications "${STAGING_DIR}/Applications"

hdiutil create -volname "Qianliyan" -srcfolder "${STAGING_DIR}" -ov -format UDZO "${DIST_DIR}/Qianliyan.dmg"
rm -rf "${STAGING_DIR}"

echo "==> Done! Distribution artifacts created:"
echo "    App: ${APP_DIR}"
echo "    DMG: ${DIST_DIR}/Qianliyan.dmg"
