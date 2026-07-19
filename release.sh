#!/usr/bin/env bash
# Lag en ny public release: ./release.sh 1.1.0 ["release-notat"]
# Bygger, zipper, tagger og publiserer på GitHub — alle installerte
# kopier auto-oppdaterer seg innen 6 timer (eller ved neste app-start).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
V="${1:?Bruk: ./release.sh <versjon, f.eks. 1.1.0> [notat]}"
NOTES="${2:-Oppdatering}"
REPO="viavicdev/pywhat"

echo "── Bygger v$V ..."
PYWHAT_VERSION="$V" "$SCRIPT_DIR/build.sh"

echo "── Zipper ..."
rm -f "$SCRIPT_DIR/.build/PyWhat.zip"
ditto -c -k --keepParent "$SCRIPT_DIR/.build/PyWhat.app" "$SCRIPT_DIR/.build/PyWhat.zip"

echo "── Tagger og publiserer ..."
cd "$SCRIPT_DIR"
git tag "v$V"
git push origin main --tags
gh release create "v$V" "$SCRIPT_DIR/.build/PyWhat.zip" \
    --repo "$REPO" --title "PyWhat v$V" --notes "$NOTES"

echo ""
echo "✓ Release v$V publisert: https://github.com/$REPO/releases/tag/v$V"
