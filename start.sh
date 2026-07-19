#!/bin/bash
# Start PyWhat menubar (Python process inspector)
set -euo pipefail
APP_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$APP_DIR/../.." && pwd)"
cd "$ROOT"
exec "$ROOT/.venv/bin/python" "$APP_DIR/pywhat_menubar.py"
