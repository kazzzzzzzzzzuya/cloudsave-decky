# Embedded CA bundle

`cacert.pem` is the Mozilla root certificate list, taken from the
[certifi](https://github.com/certifi/python-certifi) package (version 2026.10.23).
It is licensed under the Mozilla Public License 2.0.

The Linux build embeds it into `cloud_redirect.so` as a **fallback only**: it is used
when the system CA bundle fails to verify a server (curl error 60/77). Certificate
verification is never disabled.

To update it, replace `cacert.pem` and run:

```bash
python3 scripts/gen_ca_bundle.py
```
