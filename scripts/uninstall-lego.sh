#!/bin/bash
# Put the official cloud_redirect.so back (undo install-lego.sh).
set -euo pipefail
DEST_DIR="$HOME/.local/share/CloudRedirect"
DEST="$DEST_DIR/cloud_redirect.so"
BACKUP="$DEST_DIR/cloud_redirect.so.official"

[ -f "$BACKUP" ] || { echo "No backup found at $BACKUP. Re-deploy from the official CloudRedirect app instead."; exit 1; }

if pgrep -x steam >/dev/null 2>&1; then
    echo "==> Closing Steam"
    steam -shutdown >/dev/null 2>&1 || true
    for _ in $(seq 1 60); do pgrep -x steam >/dev/null 2>&1 || break; sleep 1; done
    pgrep -x steam >/dev/null 2>&1 && { echo "Steam did not close. Close it manually and run this again."; exit 1; }
fi

cp -f "$BACKUP" "$DEST.new"
mv -f "$DEST.new" "$DEST"
if [ -f "$DEST_DIR/cloud_redirect_cli.official" ]; then
    cp -f "$DEST_DIR/cloud_redirect_cli.official" "$DEST_DIR/cloud_redirect_cli.new"
    mv -f "$DEST_DIR/cloud_redirect_cli.new" "$DEST_DIR/cloud_redirect_cli"
fi
echo "==> Official cloudredirect restored. Start Steam again (or reboot)."
