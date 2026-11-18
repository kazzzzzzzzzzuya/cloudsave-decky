#!/bin/bash
# Install the LeGo fork's cloud_redirect.so over the official one (SteamOS).
# Run in Desktop Mode (Konsole). Undo with scripts/uninstall-lego.sh.
set -euo pipefail

REPO=kazzzzzzzzzzuya/cloudsave-decky
BRANCH=${CR_LEGO_BRANCH:-claude/hopeful-ramanujan-ggb0pu}
BASE=${CR_LEGO_BASE:-"https://raw.githubusercontent.com/$REPO/$BRANCH/prebuilt/linux"}
DEST_DIR="$HOME/.local/share/CloudRedirect"
DEST="$DEST_DIR/cloud_redirect.so"
BACKUP="$DEST_DIR/cloud_redirect.so.official"

say() { printf '\n==> %s\n' "$*"; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

[ -f "$DEST" ] || die "No cloudredirect found at $DEST.
Open the official CloudRedirect app and click Deploy first, then run this again."

say "Downloading the LeGo test build"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
curl -fsSL "$BASE/cloud_redirect.so" -o "$TMP/cloud_redirect.so" || die "Download failed. Check your internet connection."
curl -fsSL "$BASE/SHA256SUMS" -o "$TMP/SHA256SUMS" || die "Download failed. Check your internet connection."

say "Checking the download"
EXPECTED=$(awk '$2=="cloud_redirect.so"{print $1}' "$TMP/SHA256SUMS")
ACTUAL=$(sha256sum "$TMP/cloud_redirect.so" | awk '{print $1}')
[ -n "$EXPECTED" ] && [ "$EXPECTED" = "$ACTUAL" ] || die "Checksum mismatch, the download is damaged. Nothing was changed."
# ELF class byte must be 1 (32-bit), as Steam is 32-bit.
[ "$(od -An -tx1 -j4 -N1 "$TMP/cloud_redirect.so" | tr -d ' ')" = "01" ] || die "Downloaded file is not 32-bit. Nothing was changed."
grep -aq "LeGo fork TLS" "$TMP/cloud_redirect.so" || die "Downloaded file is not the LeGo build. Nothing was changed."
echo "OK ($ACTUAL)"

if pgrep -x steam >/dev/null 2>&1; then
    say "Closing Steam (it can't be updated while running)"
    steam -shutdown >/dev/null 2>&1 || true
    for _ in $(seq 1 60); do pgrep -x steam >/dev/null 2>&1 || break; sleep 1; done
    pgrep -x steam >/dev/null 2>&1 && die "Steam did not close. Close it manually and run this again."
fi

if grep -aq "LeGo fork TLS" "$DEST"; then
    say "A LeGo build is already installed; updating it (official backup kept)"
elif [ -f "$BACKUP" ]; then
    say "Official backup already exists; replacing the current file with the LeGo build"
    cp -f "$DEST" "$BACKUP.prev"
else
    say "Backing up the official file to $BACKUP"
    cp -f "$DEST" "$BACKUP"
fi

say "Installing"
cp -f "$TMP/cloud_redirect.so" "$DEST.new"
mv -f "$DEST.new" "$DEST"
echo "Installed LeGo build to $DEST"

cat <<'MSG'

Done! Next:
  1. Start Steam (or reboot), launch a game, then quit it.
  2. Check the result with:
       grep -aE "LeGo fork|\[TLS|TLS-DIAG|curl failed" ~/.config/CloudRedirect/cloud_redirect.log | tail -20
  3. Do NOT click "Update"/"Deploy" in the CloudRedirect app or run Headcrab
     Updater while testing: they put the official file back.

To undo:
  curl -fsSL https://raw.githubusercontent.com/kazzzzzzzzzzuya/cloudsave-decky/claude/hopeful-ramanujan-ggb0pu/scripts/uninstall-lego.sh | bash
MSG
