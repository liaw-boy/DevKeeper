#!/bin/zsh
set -e
cd "$(dirname "$0")"

echo "1. 正在以 Release 最佳化模式編譯 DevKeeper..."
swift build -c release

APP="DevKeeper.app"
rm -rf "$APP" DevKeeper.dmg
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/DevKeeper "$APP/Contents/MacOS/DevKeeper"

echo "2. 正在生成符合 Apple HIG 原生風格之應用程式圖示 (AppIcon.icns)..."
ICONSET=$(mktemp -d)/AppIcon.iconset
swift scripts/generate_icon.swift "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$(dirname "$ICONSET")"

VERSION="1.2.0"
BUILD="2026.10.23"

echo "3. 正在寫入 Info.plist 系統設定 (v$VERSION)..."
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>DevKeeper</string>
    <key>CFBundleDisplayName</key>
    <string>DevKeeper</string>
    <key>CFBundleIdentifier</key>
    <string>com.devkeeper.macos</string>
    <key>CFBundleExecutable</key>
    <string>DevKeeper</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "4. 正在對應用程式進行簽署..."
codesign --force --deep --sign - "$APP"

echo "5. 正在製作 macOS 原生安裝鏡像檔 (DevKeeper.dmg)..."
DMG_STAGE=$(mktemp -d)/dmg_stage
mkdir -p "$DMG_STAGE"
cp -R "$APP" "$DMG_STAGE/"
ln -s /Applications "$DMG_STAGE/Applications"
hdiutil create -volname "DevKeeper" -srcfolder "$DMG_STAGE" -ov -format UDZO DevKeeper.dmg >/dev/null
rm -rf "$(dirname "$DMG_STAGE")"

echo "完成！已成功打包 DevKeeper.app 與 DevKeeper.dmg。"
