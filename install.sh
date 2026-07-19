#!/usr/bin/env bash
# Installer PyWhat på en ny maskin:
#   curl -fsSL https://raw.githubusercontent.com/viavicdev/pywhat/main/install.sh | bash
# Laster ned siste release, installerer i /Applications, setter opp autostart
# (launchd) og starter appen. Appen holder seg selv oppdatert etterpå.
set -euo pipefail

REPO="viavicdev/pywhat"
API="https://api.github.com/repos/$REPO/releases/latest"

echo "── Finner siste release ..."
URL=$(curl -fsSL "$API" | grep -o '"browser_download_url": *"[^"]*PyWhat\.zip"' | head -1 | sed 's/.*"\(https[^"]*\)".*/\1/')
[ -n "$URL" ] || { echo "Fant ingen PyWhat.zip i siste release"; exit 1; }

echo "── Laster ned $URL ..."
TMP=$(mktemp -d)
curl -fsSL "$URL" -o "$TMP/PyWhat.zip"

echo "── Installerer til /Applications ..."
rm -rf /Applications/PyWhat.app
ditto -x -k "$TMP/PyWhat.zip" /Applications
xattr -dr com.apple.quarantine /Applications/PyWhat.app 2>/dev/null || true

PLIST="$HOME/Library/LaunchAgents/no.synapse.pywhat.plist"
if [ ! -f "$PLIST" ]; then
    echo "── Setter opp autostart (launchd) ..."
    mkdir -p "$HOME/Library/LaunchAgents"
    cat > "$PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>no.synapse.pywhat</string>
    <key>ProgramArguments</key>
    <array><string>/Applications/PyWhat.app/Contents/MacOS/PyWhat</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>StandardOutPath</key><string>/tmp/synapse-pywhat.log</string>
    <key>StandardErrorPath</key><string>/tmp/synapse-pywhat.log</string>
</dict>
</plist>
EOF
    launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null || launchctl load "$PLIST" 2>/dev/null || true
fi

if launchctl print "gui/$(id -u)/no.synapse.pywhat" >/dev/null 2>&1; then
    launchctl kickstart -k "gui/$(id -u)/no.synapse.pywhat"
else
    open /Applications/PyWhat.app
fi

echo ""
echo "✓ PyWhat installert og startet. Den oppdaterer seg selv fra GitHub Releases."
