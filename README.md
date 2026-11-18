# CloudRedirect — LeGo fork (testing)

A fork of [CloudRedirect](https://github.com/crghofficial/cloudredirect) by crghofficial,
focused on SteamOS handhelds (tested target: Lenovo Legion Go). It combines:

- **64-bit Steam client support** (`steamrt64`) by [The-J-01](https://github.com/The-J-01/cloudredirect)
  (branch `fix/linux-steamrt64`, upstream PR #6). See [LINUX64.md](LINUX64.md).
- **This fork's Google Drive / TLS fix** described below.

Everything below the second line is the upstream README.

## Install on 64-bit Steam (current SteamOS)

Check first: `file -L ~/.local/share/Steam/steamrt64/steam` should say *64-bit*.
You need the official CloudRedirect already set up (app installed, Deploy clicked, signed in)
and SLSsteam's 64-bit build. Back up saves you care about.

```bash
curl -fsSL https://raw.githubusercontent.com/kazzzzzzzzzzuya/cloudsave-decky/claude/hopeful-ramanujan-ggb0pu/scripts/install-lego64.sh | bash
```

Before changing anything, the installer checks your exact `steamclient.so` with read-only
probes (protobuf helper signatures, KeyValues resolver, cloud transport vtables) and stops if
your Steam build doesn't match. It then backs up the deployed `cloud_redirect.so` and
`cloud_redirect_cli` as `*.official` and installs the 64-bit pair from `prebuilt/linux64/`.

Known limits (from the 64-bit port): playtime tracking is not ported yet (save sync works
without it); live sync on SteamOS Game Mode is not yet confirmed; future Steam updates may
need new signatures.

The older 32-bit test build (`scripts/install-lego.sh`, `prebuilt/linux/`) is only for
32-bit Steam clients.

## What this fork changes

**Google Drive / cloud connection on SteamOS (Linux only)**

Some SteamOS setups fail every cloud request with `curl failed: 60` even though the
system itself reaches Google fine. This fork:

- **Logs the real reason** for connection failures: curl's error text and OpenSSL's
  verification code (`verify=20`, etc.), plus a one-time `[TLS-DIAG]` dump of the CA
  bundle, clock and relevant environment.
- **Falls back to a built-in certificate list** (Mozilla's, via certifi) when the system
  certificate bundle can't verify the server. Once the built-in list works it is used for
  the rest of the session. Certificate verification is never turned off.

Nothing else is changed: SLSsteam integration, Steam hooks and save detection are the
same as upstream.

## Install the 32-bit test build (legacy 32-bit Steam only)

You need the official CloudRedirect already set up (app installed, Deploy clicked,
signed in). Back up any saves you care about first.

```bash
curl -fsSL https://raw.githubusercontent.com/kazzzzzzzzzzuya/cloudsave-decky/claude/hopeful-ramanujan-ggb0pu/scripts/install-lego.sh | bash
```

The script downloads `prebuilt/linux/cloud_redirect.so`, checks its checksum, closes
Steam, keeps the official file as `cloud_redirect.so.official`, and swaps in the fork.

While testing, **don't click Update/Deploy in the CloudRedirect app and don't run
Headcrab Updater**: both put the official file back.

Check what happened after launching a game:

```bash
grep -aE "LeGo fork|\[TLS|TLS-DIAG|curl failed" ~/.config/CloudRedirect/cloud_redirect.log | tail -20
```

## Undo

```bash
curl -fsSL https://raw.githubusercontent.com/kazzzzzzzzzzuya/cloudsave-decky/claude/hopeful-ramanujan-ggb0pu/scripts/uninstall-lego.sh | bash
```

## Building

```bash
linux-build/build.sh          # 32-bit: Docker, Ubuntu 22.04 + GCC 12 -> dist/cloud_redirect.so
# 64-bit: scripts/build-linux64.sh (upstream PR #6), or in Docker without
# Debian/Launchpad access:
docker run --rm -v "$PWD":/src -v "$PWD/.cache/linux-build64":/work64 ubuntu:20.04 \
    bash /src/linux-build/build64-in-container.sh   # -> dist64/
```

OpenSSL 3.3.2 and curl 8.10.1 are built statically for 32-bit, matching upstream's
versions. `tests/linux/run_tls_fallback_test.sh` checks the fallback logic.

---

# CloudRedirect

""Steam Cloud"" for 'lua' games.

**This the only official source for CloudRedirect. Any other websites are not operated by me or are otherwise endorsed by this project. At least one of those fake sites was actively distributing malware!**

> ****This software is experimental and under active development.**** The underlying techniques are fairly insane. What this software tries to do is nuts to attempt. This software could damage your save files and probably will! It could overwrite your saves, cause weird conflicts, make your saves disappear, make you cry. Back up any saves you care about before using this software.

But it probably won't. It's been very solid for a long time.

>****Do not use this if you do not actively want cloud saves for "lua" games. If all you care about is the Steam Cloud error, disable Steam Cloud in properties for that game.****

## What it does

First, some back story:

Once upon a time, there was a tool called SteamTools. SteamTools supported cloud saving, kind of.

Later, Valve patched the (sinful) thing SteamTools did to sync saves. Specifically, SteamTools rewrote requests to AppID 760, which is Steam Screenshots. It sent all Steam Cloud requests for non-owned AppIDs there. It did not create prefixes for each individual game, which means that each lua app shared the saves with all others. This can cause saves to conflict if multiple games use the same save file name. This also means that your saves are replicated in the `Steam/Userdata/<steamid>/<appid for lua game>` folder for each lua app.

It also did not support Steam AutoCloud games at all. It would simply show a fake success message for those games.

What _this_ tool does is redirect Steam Cloud requests for games that are injected to Google Drive/OneDrive/a local folder, including AutoCloud games. Everything is native inside the Steam Client, but the actual data is read/written to and from your cloud account. This was much harder to do than just redirecting read/write to an AppID that your account owns, but it was fun to make. It also is less likely to piss off Valve.

## How it works

CloudRedirect for Windows consists of a C++ DLL and a WPF companion app:

1. The companion app is used to copy the DLL to your Steam folder and let the user login to their cloud provider.
2. The DLL hooks Steam's internal cloud save RPC handlers via ~~vtable interception~~ black magic.
3. When a lua game attempts to read or write cloud save data, the DLL intercepts the calls and redirects it. If the game is owned, the game uses normal Steam Cloud as expected. If a lua is present that only unlocks DLC, the game will use normal Steam Cloud.
4. More dark magic occurs. Saves sync. Bytes flow. This all is visible in the Steam UI and looks identical to normal Steam Cloud functionality.

Same rough idea on Linux, but involving a flatpak application and a library that is loaded on steam startup instead. 
   
## Supported cloud providers

- **Google Drive**
- **OneDrive**
- **Cloudflare R2**
- **S3-Compatible** - AWS S3, MinIO, Backblaze B2, Wasabi, DigitalOcean Spaces, and any self-hosted S3 server.
- **Local folder / mapped drive** - by request of literally one user.

With more to come over time. 

## Usage (Windows)

Grab the latest release from the [Releases page](https://github.com/crghofficial/cloudredirect/releases).

Run the EXE. Pick your mode - STfixer mode for fixes to ST bugs, CloudRedirect mode for the good stuff. In Setup, hit 'Run All Patches'. Go to the Cloud Provider tab, select your provider. If it is a cloud provider, sign in to it.

That's it. Go launch Steam and watch the magic.

## Usage (Linux)

Edit your SLSsteam config, set DisableCloud to No. 


```curl -fsSL headcrab.pages.dev | bash```

Open the CloudRedirect app, sign into a provider.

Edit your SLS config. The games you want to sync must be specified under AdditionalApps in your SLS config. This requirement will go away in the future. 

Now launch Steam and watch your games sync!

## Building from source (Windows)

### Prerequisites

- Visual Studio 2022 (or Build Tools) with the C++ and .NET 8 workloads
- CMake 3.20+

### Build

```bash
cmake -B build -G "Visual Studio 17 2022" -A x64
cmake --build build --config Release
```

This builds both the C++ DLL (`build/Release/cloud_redirect.dll`) and publishes the WPF app (`ui/bin/publish/CloudRedirect.exe`). The DLL is automatically embedded into the executable.

Or don't build it? Building Windows apps is pain.

## Building from source (Linux)

For current x86-64 Steam clients, see [Linux x86-64 build and validation](LINUX64.md). The `LINUX_32BIT` instructions below target legacy i386 clients.


Oooooh boy. Yeah. Have fun. 

You need to build against glibc 2.31 or older. Ubuntu 20.04 would work, if you dislike yourself. There's also an ancient version of Fedora that fits the bill. Or Debian 11. Distrobox is the way, here. Don't even bother trying to build under whatever distro you daily, you'll wind up fighting it for no reason. Distrobox exists for a reason. 

If you are building under Ubuntu 20.04, GCC 12 is needed along with the 32-bit multilib stuff. System cmake is ancient garbage, you'll have to update it.

Then specify -DLINUX_32BIT=ON and wham bam.

Isn't building for weird distros _fun?_

## Contibuting

CloudRedirect is open source. I welcome PRs. I love PRs.

I don't _love_ downstream forks. You have a right to fork and do what you want, but if you make something useful, if you fix issues...I'd much prefer they be sent upstream! Help me help you! If you identify a problem/add a provider/improve the tool in any way, please consider submitting your changes as a PR, rather than keeping them in a downstream fork.
