# Prebuilt 64-bit test build (SteamOS, Steam `steamrt64` client)

The-J-01's x86-64 port (upstream PR #6) plus this fork's TLS diagnostics and
embedded-CA fallback. Built with `linux-build/build64-in-container.sh`.

`linux_kv64_resolver_tests`, `linux_vtable_probe` and `check-steamclient64-sigs.py`
are read-only probes that `scripts/install-lego64.sh` runs against your
`steamclient.so` before installing anything.
