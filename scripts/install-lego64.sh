#!/bin/bash
# Install the 64-bit LeGo build of cloudredirect (for Steam's 64-bit client,
# steamrt64) over the deployed one. Checks your exact Steam build first and
# changes nothing if any check fails. Run in Desktop Mode (Konsole).
# Undo with scripts/uninstall-lego.sh.
set -euo pipefail

REPO=kazzzzzzzzzzuya/cloudsave-decky
BRANCH=${CR_LEGO_BRANCH:-claude/hopeful-ramanujan-ggb0pu}
BASE=${CR_LEGO_BASE:-"https://raw.githubusercontent.com/$REPO/$BRANCH/prebuilt/linux64"}
CR_DIR="$HOME/.local/share/CloudRedirect"
SLS="$HOME/.local/share/SLSsteam/SLSsteam.so"
STEAM_DIR="$HOME/.local/share/Steam"

say() { printf '\n==> %s\n' "$*"; }
die() { printf '\nERROR: %s\nNothing was changed.\n' "$*" >&2; exit 1; }
is64() { [ -f "$1" ] && [ "$(od -An -tx1 -j4 -N1 "$1" | tr -d ' ')" = "02" ]; }

say "Checking your setup"
[ -d "$CR_DIR" ] || die "No CloudRedirect folder at $CR_DIR. Set up the official CloudRedirect (app -> Deploy) first."
is64 "$SLS" || die "SLSsteam at $SLS is missing or not 64-bit. This build is only for 64-bit Steam."
command -v python3 >/dev/null || die "python3 not found."

STEAMCLIENT=""
pid=$(pgrep -x steam | head -1 || true)
if [ -n "$pid" ]; then
    STEAMCLIENT=$(grep -o '/[^ ]*steamclient\.so$' "/proc/$pid/maps" 2>/dev/null | head -1 || true)
fi
if [ -z "$STEAMCLIENT" ] || ! is64 "$STEAMCLIENT"; then
    STEAMCLIENT=""
    for c in "$STEAM_DIR/steamrt64/steamclient.so" "$STEAM_DIR/linux64/steamclient.so"; do
        if is64 "$c"; then STEAMCLIENT=$c; break; fi
    done
fi
[ -n "$STEAMCLIENT" ] || die "Could not find Steam's 64-bit steamclient.so."
echo "Steam client library: $STEAMCLIENT"
echo "Steam build: $(grep -ahoE '"version"[[:space:]]*"[0-9]+"' "$STEAM_DIR"/package/steam_client_*.manifest 2>/dev/null | grep -oE '[0-9]+' | head -1 || echo unknown)"

say "Downloading the 64-bit LeGo build"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
FILES="cloud_redirect.so cloud_redirect_cli linux_kv64_resolver_tests linux_vtable_probe check-steamclient64-sigs.py"
curl -fsSL "$BASE/SHA256SUMS" -o "$TMP/SHA256SUMS" || die "Download failed. Check your internet connection."
for f in $FILES; do
    curl -fsSL "$BASE/$f" -o "$TMP/$f" || die "Download of $f failed."
done
(cd "$TMP" && sha256sum -c --quiet SHA256SUMS) || die "Checksum mismatch, the download is damaged."
chmod +x "$TMP/cloud_redirect_cli" "$TMP/linux_kv64_resolver_tests" "$TMP/linux_vtable_probe"
is64 "$TMP/cloud_redirect.so" && is64 "$TMP/cloud_redirect_cli" || die "Downloaded files are not 64-bit."
grep -aq "LeGo fork TLS" "$TMP/cloud_redirect.so" || die "Downloaded file is not the LeGo build."
echo "OK"

say "Checking your Steam build is compatible (read-only)"
fail=0
echo "-- protobuf helper signatures:"
python3 "$TMP/check-steamclient64-sigs.py" "$STEAMCLIENT" || fail=1
echo "-- KeyValues/app info resolver:"
"$TMP/linux_kv64_resolver_tests" "$STEAMCLIENT" || fail=1
echo "-- cloud transport vtables:"
set +e
LD_LIBRARY_PATH="$(dirname "$STEAMCLIENT")${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
    "$TMP/linux_vtable_probe" "$STEAMCLIENT"
rc=$?
set -e
if [ $rc -eq 5 ]; then
    echo "(could not load steamclient.so outside Steam; skipped, cloudredirect checks this again at startup)"
elif [ $rc -ne 0 ]; then
    echo "vtable probe failed (code $rc)"; fail=1
fi
[ $fail -eq 0 ] || die "Your Steam build doesn't match what this cloudredirect build expects.
Send the output above to get it updated."
echo "All checks passed."

if pgrep -x steam >/dev/null 2>&1; then
    say "Closing Steam (it can't be updated while running)"
    steam -shutdown >/dev/null 2>&1 || true
    for _ in $(seq 1 60); do pgrep -x steam >/dev/null 2>&1 || break; sleep 1; done
    pgrep -x steam >/dev/null 2>&1 && die "Steam did not close. Close it manually and run this again."
fi

say "Backing up the current files"
for f in cloud_redirect.so cloud_redirect_cli; do
    if [ -f "$CR_DIR/$f" ] && ! grep -aq "LeGo fork TLS" "$CR_DIR/$f" && [ ! -f "$CR_DIR/$f.official" ]; then
        cp -f "$CR_DIR/$f" "$CR_DIR/$f.official" && echo "saved $f.official"
    fi
done

say "Installing"
for f in cloud_redirect.so cloud_redirect_cli; do
    install -m 755 "$TMP/$f" "$CR_DIR/$f.new"
    mv -f "$CR_DIR/$f.new" "$CR_DIR/$f"
done
echo "Installed 64-bit LeGo build to $CR_DIR"

cat <<'MSG'

Done! Next:
  1. Quick connection test (no Steam needed):
       ~/.local/share/CloudRedirect/cloud_redirect_cli --cli list-remote-app-ids gdrive 1107909673
  2. Start Steam, open a game, save, quit. Then:
       grep -aE "CloudRedirect build|active in process|Hook|x86-64|LeGo fork|\[TLS|curl failed|Init failed|NOT installed" ~/.config/CloudRedirect/cloud_redirect.log | tail -25
  3. Don't click Update/Deploy in the CloudRedirect app or run Headcrab Updater
     while testing: they put the official (32-bit) files back.

To undo:
  curl -fsSL https://raw.githubusercontent.com/kazzzzzzzzzzuya/cloudsave-decky/claude/hopeful-ramanujan-ggb0pu/scripts/uninstall-lego.sh | bash
MSG
