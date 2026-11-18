#!/bin/bash
# Builds the 32-bit cloud_redirect.so for SteamOS inside Ubuntu 22.04 (GCC 12, glibc 2.35).
# Run via linux-build/build.sh, or directly inside an ubuntu:22.04 container with
# the repository mounted at /src. Output goes to /src/dist/.
# Upstream targets glibc 2.31 with a PPA GCC 12; SteamOS ships a much newer
# glibc, so building on 22.04 with its stock GCC 12 is fine for SteamOS.
set -euo pipefail

OPENSSL_VER=3.3.2
CURL_VER=8.10.1
GCC_VER=${GCC_VER:-12}
SRC=/src
WORK=/work
DEPS=$WORK/install32
JOBS=$(nproc)

export DEBIAN_FRONTEND=noninteractive
if ! command -v g++-$GCC_VER >/dev/null || ! dpkg -s gcc-multilib >/dev/null 2>&1; then
    apt-get update -q
    apt-get install -y -q --no-install-recommends \
        ca-certificates curl perl make pkg-config python3-pip git file binutils \
        gcc-$GCC_VER g++-$GCC_VER gcc-$GCC_VER-multilib g++-$GCC_VER-multilib gcc-multilib
fi
if ! cmake --version 2>/dev/null | grep -qE 'version 3\.(2[0-9]|[3-9][0-9])'; then
    python3 -m pip install -q 'cmake>=3.20,<3.31'
fi

export CC="gcc-$GCC_VER -m32" CXX="g++-$GCC_VER -m32"
mkdir -p "$WORK" "$DEPS"
cd "$WORK"

if [ ! -f "$DEPS/lib/libssl.a" ]; then
    [ -f openssl-$OPENSSL_VER.tar.gz ] || curl -fsSLO \
        "https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL_VER/openssl-$OPENSSL_VER.tar.gz"
    rm -rf openssl-$OPENSSL_VER && tar xf openssl-$OPENSSL_VER.tar.gz
    (cd openssl-$OPENSSL_VER &&
        ./Configure linux-x86 no-shared no-tests no-docs no-module no-engine \
            --prefix="$DEPS" --libdir=lib --openssldir=/etc/ssl -fPIC &&
        make -j"$JOBS" build_libs >/dev/null &&
        make install_dev >/dev/null)
fi

if [ ! -f "$DEPS/lib/libcurl.a" ]; then
    CURL_TAG=curl-${CURL_VER//./_}
    [ -f curl-$CURL_VER.tar.gz ] || curl -fsSLO \
        "https://github.com/curl/curl/releases/download/$CURL_TAG/curl-$CURL_VER.tar.gz"
    rm -rf curl-$CURL_VER && tar xf curl-$CURL_VER.tar.gz
    (cd curl-$CURL_VER &&
        CFLAGS="-fPIC" PKG_CONFIG_PATH="$DEPS/lib/pkgconfig" ./configure --host=i686-pc-linux-gnu \
            --prefix="$DEPS" --disable-shared --enable-static --with-pic \
            --with-openssl="$DEPS" --without-zlib --without-brotli --without-zstd \
            --without-libpsl --without-libidn2 --without-nghttp2 --without-libssh2 \
            --disable-ldap --disable-ldaps --disable-rtsp --disable-dict --disable-telnet \
            --disable-tftp --disable-pop3 --disable-imap --disable-smtp --disable-gopher \
            --disable-mqtt --disable-manual --disable-docs \
            --without-ca-bundle --without-ca-path --without-ca-fallback >/dev/null &&
        make -j"$JOBS" -C lib >/dev/null &&
        make -C lib install >/dev/null && make -C include install >/dev/null)
fi

rm -rf "$WORK/build"
cmake -S "$SRC" -B "$WORK/build" -DCMAKE_BUILD_TYPE=Release -DLINUX_32BIT=ON \
    -DDEPS32_PREFIX="$DEPS" -DCMAKE_C_COMPILER=gcc-$GCC_VER -DCMAKE_CXX_COMPILER=g++-$GCC_VER \
    ${CR_GIT_SHA:+-DCR_GIT_SHA=$CR_GIT_SHA}
cmake --build "$WORK/build" --target cloud_redirect cloud_redirect_cli -j"$JOBS"

mkdir -p "$SRC/dist"
cp "$WORK/build/cloud_redirect.so" "$WORK/build/cloud_redirect_cli" "$SRC/dist/"
strip --strip-unneeded "$SRC/dist/cloud_redirect.so" "$SRC/dist/cloud_redirect_cli" || true
(cd "$SRC/dist" && sha256sum cloud_redirect.so cloud_redirect_cli > SHA256SUMS)

echo "== Built:"
file "$SRC/dist/cloud_redirect.so"
echo "== Highest glibc / libstdc++ symbol versions required:"
objdump -T "$SRC/dist/cloud_redirect.so" | grep -oE 'GLIBC_[0-9.]+' | sort -uV | tail -1
objdump -T "$SRC/dist/cloud_redirect.so" | grep -oE 'GLIBCXX_[0-9.]+' | sort -uV | tail -1 || true
cat "$SRC/dist/SHA256SUMS"
