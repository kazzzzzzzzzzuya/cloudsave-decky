#!/bin/bash
# Runs inside the build container after linux-build/build-in-container.sh has
# produced /work/install32. Needs network access to the test URL.
#
#   TRUSTED_CA  PEM that can verify TEST_URL (the real CA chain, or a proxy CA)
#   TEST_URL    https URL to fetch (default: Google Drive API, returns 401)
set -euo pipefail
TEST_URL=${TEST_URL:-https://www.googleapis.com/drive/v3/about}
TRUSTED_CA=${TRUSTED_CA:-/etc/ssl/certs/ca-certificates.crt}
DEPS=/work/install32
OUT=/work/tlstest
mkdir -p "$OUT"

# An unrelated, self-made CA: a "system bundle" that cannot verify anything.
openssl req -x509 -newkey rsa:2048 -nodes -days 30 -subj "/CN=Bogus Test CA" \
    -keyout "$OUT/bogus.key" -out "$OUT/bogus.pem" >/dev/null 2>&1

gen_inc() {  # gen_inc <pem> <out.inc>
    python3 - "$1" "$2" <<'PY'
import sys
pem = open(sys.argv[1], "rb").read()
with open(sys.argv[2], "w") as f:
    f.write(f"static const unsigned char kEmbeddedCaBundle[{len(pem)}] = {{")
    f.write(",".join(str(b) for b in pem))
    f.write("};\n")
    f.write(f"static const size_t kEmbeddedCaBundleCerts = {pem.count(b'BEGIN CERTIFICATE')};\n")
PY
}

build() {  # build <name> <inc>
    g++-12 -m32 -std=c++20 -O1 -D_GLIBCXX_USE_CXX11_ABI=0 -D_FILE_OFFSET_BITS=64 \
        -DCR_TEST_EMBEDDED_CA_INC="\"$2\"" \
        -I/src/src/common -I/src/src/platform/linux -I"$DEPS/include" \
        /src/tests/linux/tls_fallback_test.cpp -o "$OUT/$1" \
        "$DEPS/lib/libcurl.a" "$DEPS/lib/libssl.a" "$DEPS/lib/libcrypto.a" -lpthread -ldl
}

gen_inc "$TRUSTED_CA" "$OUT/trusted.inc"
gen_inc "$OUT/bogus.pem" "$OUT/bogus.inc"
build test_trusted_embedded "$OUT/trusted.inc"
build test_bogus_embedded "$OUT/bogus.inc"

rc=0
echo "== 1. system CA broken, embedded CA good -> falls back once, then sticks"
SSL_CERT_FILE="$OUT/bogus.pem" SSL_CERT_DIR="$OUT" "$OUT/test_trusted_embedded" fallback "$TEST_URL" || rc=1
echo "== 2. system CA good -> no fallback, no diagnostics"
SSL_CERT_FILE="$TRUSTED_CA" "$OUT/test_bogus_embedded" system "$TEST_URL" || rc=1
echo "== 3. both broken -> fails with the real reason in the log"
SSL_CERT_FILE="$OUT/bogus.pem" SSL_CERT_DIR="$OUT" "$OUT/test_bogus_embedded" fail "$TEST_URL" || rc=1
[ $rc -eq 0 ] && echo "ALL TLS FALLBACK TESTS PASSED" || echo "SOME TLS FALLBACK TESTS FAILED"
exit $rc
