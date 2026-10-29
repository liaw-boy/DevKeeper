#!/usr/bin/env bash
# Builds DevKeeper-x86_64.AppImage from linux-gui plus a prebuilt devkeeper-cli.
# Usage: build-appimage.sh /path/to/devkeeper-cli   (run from linux-gui/, Linux x86_64 only)
set -euo pipefail

CLI="${1:?path to devkeeper-cli required}"
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/.."
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

python3 -m venv "$WORK/venv"
"$WORK/venv/bin/pip" install -q "$ROOT" "pyinstaller>=6,<7"
"$WORK/venv/bin/pyinstaller" --noconfirm --name devkeeper-gui --distpath "$WORK/dist" \
  --workpath "$WORK/build" --specpath "$WORK" "$HERE/launcher.py" > /dev/null

APPDIR="$WORK/DevKeeper.AppDir"
mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/share/applications"
cp -r "$WORK/dist/devkeeper-gui/." "$APPDIR/usr/bin/"
cp "$CLI" "$APPDIR/usr/bin/devkeeper-cli"
chmod +x "$APPDIR/usr/bin/devkeeper-cli"
cp "$HERE/devkeeper-gui.desktop" "$APPDIR/"
cp "$HERE/devkeeper-gui.desktop" "$APPDIR/usr/share/applications/"
"$WORK/venv/bin/python" "$HERE/make_icon.py" "$APPDIR/devkeeper-gui.png"
cat > "$APPDIR/AppRun" <<'RUN'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
# The bundled CLI is the default; an explicit DEVKEEPER_CLI still wins.
export DEVKEEPER_CLI="${DEVKEEPER_CLI:-$HERE/usr/bin/devkeeper-cli}"
exec "$HERE/usr/bin/devkeeper-gui" "$@"
RUN
chmod +x "$APPDIR/AppRun"

# Pinned tool version, downloaded over HTTPS from the project's release page (no checksum is verified yet).
TOOL_URL="https://github.com/AppImage/appimagetool/releases/download/1.9.0/appimagetool-x86_64.AppImage"
curl -fsSL "$TOOL_URL" -o "$WORK/appimagetool"
chmod +x "$WORK/appimagetool"
ARCH=x86_64 "$WORK/appimagetool" --appimage-extract-and-run "$APPDIR" "$ROOT/DevKeeper-x86_64.AppImage"
echo "built: $ROOT/DevKeeper-x86_64.AppImage"
