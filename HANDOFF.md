# Handoff: cloud saves on Legion Go + next project (Decky status plugin)

Context cache from a previous Claude session, for continuing the work in a new one.
IDs are written as placeholders (`<ACCOUNT_ID>` etc.) because this repo is public;
ask the user for the real values if needed.

## About the user

- Plays on a **Lenovo Legion Go running SteamOS**. Tests everything on the device and pastes
  Konsole output or photos back. Often away from the device; can't test immediately.
- Prefers **plain, simple explanations** and **step-by-step commands** (one paste-able block).
- When they say "just answer first" / "just a question", **answer only, don't build**.
- Maintains their own Decky plugins: **LeGo-decky-toolbox** (MIT) and **Frame-Suite**, both
  under GitHub user `kazzzzzzzzzzuya`. New plugins should match their look and layout.

## Current setup on the device (working as of 2026-11-21)

| Piece | State |
|---|---|
| Steam client | **64-bit** `~/.local/share/Steam/steamrt64/steam`, build **1794536281** |
| SLSsteam | 64-bit, loaded via `LD_AUDIT=…/library-inject.so:…/SLSsteam.so` in `~/.local/share/Steam/steam.sh` |
| SLSsteam config | `~/.config/SLSsteam/config.yaml`: `DisableCloud: no`, games under `AdditionalApps:` as a **block list** (cloudredirect's parser ignores inline `[..]` lists and quoted IDs) |
| cloudredirect | **The-J-01's 64-bit fork**, version `2.6.6+585a8cb`, at `~/.local/share/CloudRedirect/cloud_redirect.so` + `cloud_redirect_cli` (64-bit). Loaded into Steam and syncing. |
| Provider | Google Drive (`gdrive`) |
| Leftovers | Possibly `cloud_redirect.so.official` / `cloud_redirect_cli.official` (old 32-bit official backups from an earlier test). Harmless. **Don't run `scripts/uninstall-lego.sh`**: it would restore the 32-bit files over the working 64-bit build. |

Updating through the official CloudRedirect app (Update/Deploy) or Headcrab Updater may
replace The-J-01's build with the official 32-bit one until upstream merges PR #6.

### How we got here (history, short)

1. Every game showed a Steam Cloud error, and Stellar Blade's saves showed "0 files / 0 B".
2. Stellar Blade (app 3489700) was saving under a **placeholder Steam ID folder**, not the
   user's real one. Fixed by moving the save into the real-ID folder and leaving a **symlink**
   `SaveGames/<PLACEHOLDER_ID> -> <REAL_STEAMID64>`. **Must stay**, or the game saves where
   cloudredirect can't see it.
   Path: `~/.local/share/Steam/steamapps/compatdata/3489700/pfx/drive_c/users/steamuser/AppData/Local/SB/Saved/SaveGames/`
3. Old official cloudredirect logged `curl failed: 60` on every Google Drive request inside the
   32-bit Steam, while system curl and `cloud_redirect_cli` worked outside Steam.
4. Real root cause of the cloud errors: **Steam switched to 64-bit**; the official
   `cloud_redirect.so` is 32-bit only, so it wasn't loading at all.
5. User installed The-J-01's 64-bit fork → syncing works. Verified on 2026-11-21: Steam asked for
   3 uploads at game exit; all `CommitFileUpload … succeeded=1`; published at CN=13; cloud blob
   sizes match local files.
6. Two old files still sit directly in `SaveGames/` (outside the ID folder, from 16 Nov, uploaded
   18 Nov). The game doesn't use them; they caused a "stuck since Wednesday" scare. Leave them.

## Where cloudredirect keeps things (Linux)

- Log: `~/.config/CloudRedirect/cloud_redirect.log` (truncated at 10 MB; may contain binary bytes, use `grep -a`)
- Config: `~/.config/CloudRedirect/config.json`; local state under `~/.config/CloudRedirect/storage/`
  (local metadata, pending-ops journal, staging, stats). Check the exact layout on device with `ls -R`.
- Google tokens: libsecret, or `~/.config/CloudRedirect/google_tokens.json` (0600). **Never read or print tokens.**
- Cloud layout (Google Drive, folder `CloudRedirect`):
  `<ACCOUNT_ID>/<APPID>/{cn.cloudredirect, state.cloudredirect, file_tokens.cloudredirect, root_token.cloudredirect, blobs/<save path>/<sha1>}`

### Read-only CLI (JSON output, safe to call)

```bash
~/.local/share/CloudRedirect/cloud_redirect_cli --cli list-remote-app-ids gdrive <ACCOUNT_ID>
# {"success":true,"app_ids":["1293830","3669870",...]}
~/.local/share/CloudRedirect/cloud_redirect_cli --cli list-remote-app-files gdrive <ACCOUNT_ID> <APPID>
# {"success":true,"complete":true,"files":[{"path":"...","size":N,"modified_time":UNIX},...]}
~/.local/share/CloudRedirect/cloud_redirect_cli --cli auth-status gdrive
```

Other CLI commands exist (`delete-remote-app`, `delete-blobs`, `gc-blobs`, `migrate`, …). **They
change cloud data: a status plugin must not call them.**

`<ACCOUNT_ID>` is the short Steam account ID: SteamID64 − 76561197960265728. It's also the
folder name under `~/.local/share/Steam/userdata/`.

### Useful log lines (per app)

```
[NS] BeginBatch app=<APPID> batchId=… assignedCN=… uploads=N deletes=M
[NS-UP] BeginFileUpload app=<APPID> file=%WinAppDataLocal%<path>
[NS-UP] CommitFileUpload app=<APPID> file=… succeeded=1
[NS] CompleteBatch app=<APPID>: local CN advanced to N + manifest saved
[NS] CompleteBatch(pub): publish 1/4 succeeded for app <APPID> at CN=N
[NS] CompleteBatch(pub): all publish attempts exhausted …   (failure)
[NS-CL] GetAppFileChangelist app=<APPID> … INCONCLUSIVE cloud fetch …   (couldn't reach cloud)
[Hook] IsCloudEnabledForApp(<APPID>) -> true (namespace app)
[GDrive] curl failed: <code> …   (network/TLS failure)
CloudRedirect build <version> / cloud_redirect.so active in process 'steam'   (startup)
GetAutoCloudFileList: app <APPID> rule root=… resolved='…'   (where it scans for saves)
```

Timestamps are `[HH:MM:SS]` only, with no date; the device clock is UTC. Combine with file mtimes
or the cloud `modified_time` for dates.

## Next project: Decky plugin with per-game save status (+ OpenSave)

The user asked whether it's possible (answered **yes, both**) and hasn't said "go" yet.
**Confirm before building.**

### Part 1: cloudredirect status per game (do first)

- List SLSsteam games (from `AdditionalApps`) with names (Steam library/appinfo) and, per game:
  last upload time and result, files and size locally vs in the cloud, match/mismatch, errors
  (e.g. `curl failed`, hooks not loaded after a Steam update, app missing from the cloud).
- Global health: is `cloud_redirect.so` 64-bit and mapped into the running `steam` process
  (`/proc/<pid>/maps`), Steam build number, auth status.
- **Read-only**: parse the log, read local state, call only the read-only CLI commands above.
  Cache cloud listings; don't hammer Google Drive.
- No live progress bar: uploads take ~1–3 s at game exit, so show status, not percentages.

### Part 2: OpenSave for emulators / non-Steam games

- OpenSave: https://github.com/Liquid-co/OpenSave (MIT, Go, active). P2P + optional Google
  Drive/Dropbox/OneDrive/WebDAV/NAS backup, snapshots, Ludusavi manifest + emulator detection,
  full `opensave` CLI and a background service. It has its own Decky plugin in
  `opensave-decky-plugin/` (README says "untested on hardware"). On SteamOS install the
  **Flatpak** from GitHub Releases (not the tarball, and not the `curl opensave.org/install.sh`
  one-liner, which hasn't been verified).
- Plan: show OpenSave-tracked games in the same list and offer "Sync now", via its CLI/daemon.
  **Check what the CLI actually outputs before promising features.**
- **One tool per game:** cloudredirect for SLSsteam/Steam games, OpenSave for emulators and
  non-Steam games. Never let both manage the same save folder; the plugin should prevent it.

### Constraints

- Nothing can be tested on the device from a cloud session; expect several install → screenshot →
  fix rounds.
- Save data is precious: back it up first, read-only by default, and an undo path for anything
  that writes.

## This repo (`kazzzzzzzzzzuya/cloudsave-decky`, branch `claude/hopeful-ramanujan-ggb0pu`)

A fork of cloudredirect: upstream `4e81e49` + The-J-01's `fix/linux-steamrt64` (merged) + the
previous session's work:

- `src/platform/linux/http_transport_linux.cpp`: logs curl's error text and the OpenSSL verify
  code, a one-time `[TLS-DIAG]` dump, and falls back to an embedded Mozilla CA list
  (`third_party/ca-bundle/`, generated `ca_bundle_embedded.inc`) when the system CA fails.
  Never disables verification. Tests: `tests/linux/`.
- `linux-build/build.sh`: 32-bit build in Docker. `linux-build/build64-in-container.sh`: 64-bit
  build in `ubuntu:20.04` with conda-forge GCC 12 (the Debian/Launchpad/openssl.org/curl.se
  hosts that `scripts/build-linux64.sh` uses were blocked in that environment).
- `scripts/install-lego.sh` (32-bit), `scripts/install-lego64.sh` (64-bit; runs read-only probes
  against the user's `steamclient.so` and refuses on mismatch), `scripts/uninstall-lego.sh`,
  `scripts/check-steamclient64-sigs.py`.
- `prebuilt/linux/` and `prebuilt/linux64/`: test builds. **Not in use**: the user runs
  The-J-01's build. The TLS fix only matters if `curl failed: 60` comes back.

The Decky plugin should go in **its own folder or repo**, not mixed into the cloudredirect source.
