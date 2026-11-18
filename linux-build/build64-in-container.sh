#!/bin/bash
# x86-64 build of cloud_redirect.so for the 64-bit Steam client (steamrt64).
# Runs inside ubuntu:20.04 with the repo at /src and a cache dir at /work.
# Equivalent to scripts/build-linux64.sh, but takes its toolchain from
# conda-forge (GCC 12 targeting glibc 2.17) and its OpenSSL/curl tarballs from
# GitHub, for build hosts that cannot reach Debian, Launchpad, openssl.org or
# curl.se. Same dependency versions and checksums as scripts/build-linux64.sh.
set -euo pipefail

SRC=/src
WORK=/work64
DEPS=$WORK/static
JOBS=$(nproc)
MAMBA_VER=2.3.3-0
OPENSSL_VER=3.5.4
OPENSSL_SHA=967311f84955316969bdb1d8d4b983718ef42338639c621ec4c34fddef355e99
CURL_VER=8.23.0
CURL_SHA=8dadd7d2536a314f982ad05a651b713f426bf7d02cc2c76cffb9796f2218e6c5

export DEBIAN_FRONTEND=noninteractive
if ! command -v make >/dev/null || ! command -v perl >/dev/null || ! command -v readelf >/dev/null; then
    apt-get update -q
    apt-get install -y -q --no-install-recommends ca-certificates curl make perl bzip2 xz-utils binutils python3 file
fi
mkdir -p "$WORK" "$DEPS"
cd "$WORK"

# Toolchain: conda-forge GCC 12 (sysroot glibc 2.17), cmake, ninja.
if [ ! -x "$WORK/env/bin/x86_64-conda-linux-gnu-g++" ]; then
    [ -x "$WORK/micromamba" ] || curl -fsSL -o "$WORK/micromamba" \
        "https://github.com/mamba-org/micromamba-releases/releases/download/$MAMBA_VER/micromamba-linux-64"
    chmod +x "$WORK/micromamba"
    "$WORK/micromamba" create -y -q -r "$WORK/mamba-root" -p "$WORK/env" -c conda-forge \
        'gxx_linux-64=12' 'gcc_linux-64=12' 'cmake>=3.20' ninja 'sysroot_linux-64=2.17'
fi
export PATH="$WORK/env/bin:$PATH"
CC=x86_64-conda-linux-gnu-gcc
CXX=x86_64-conda-linux-gnu-g++
# conda's compiler wrappers expect CONDA_BUILD_SYSROOT; plain invocation finds its sysroot itself.
$CXX --version | head -1

fetch() {  # fetch <url> <file> <sha256>
    [ -f "$2" ] || curl -fsSL -o "$2" "$1"
    echo "$3  $2" | sha256sum -c - >/dev/null || { echo "Checksum mismatch: $2"; exit 1; }
}

if [ ! -f "$DEPS/lib/libcrypto.a" ]; then
    fetch "https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL_VER/openssl-$OPENSSL_VER.tar.gz" openssl.tar.gz $OPENSSL_SHA
    rm -rf openssl-src && mkdir openssl-src && tar -xzf openssl.tar.gz --strip-components=1 -C openssl-src
    (cd openssl-src &&
        CC=$CC ./Configure linux-x86_64 no-shared no-tests no-module no-docs -fPIC \
            --prefix="$DEPS" --libdir=lib --openssldir=/etc/ssl >/dev/null &&
        make -j"$JOBS" build_libs >/dev/null && make install_dev >/dev/null)
fi

if [ ! -f "$DEPS/lib/libcurl.a" ]; then
    fetch "https://github.com/curl/curl/releases/download/curl-${CURL_VER//./_}/curl-$CURL_VER.tar.xz" curl.tar.xz $CURL_SHA
    rm -rf curl-src && mkdir curl-src && tar -xJf curl.tar.xz --strip-components=1 -C curl-src
    (cd curl-src &&
        CC=$CC CPPFLAGS="-I$DEPS/include" LDFLAGS="-L$DEPS/lib" LIBS='-ldl -lpthread' PKG_CONFIG=/bin/false \
        ./configure --prefix="$DEPS" --disable-shared --enable-static --with-pic \
            --disable-docs --disable-manual --with-ca-bundle=/etc/ssl/certs/ca-certificates.crt \
            --with-openssl="$DEPS" --without-zlib --without-libpsl --without-zstd --without-brotli \
            --without-libidn2 --without-nghttp2 --without-libssh2 --without-librtmp --without-ngtcp2 \
            --without-quiche --disable-ldap --disable-ldaps --disable-ftp --disable-file --disable-dict \
            --disable-telnet --disable-tftp --disable-imap --disable-pop3 --disable-smtp --disable-smb \
            --disable-gopher --disable-mqtt >/dev/null &&
        make -j"$JOBS" -C lib >/dev/null && make -C lib install >/dev/null && make -C include install >/dev/null)
fi

rm -rf "$WORK/build"
cmake -S "$SRC" -B "$WORK/build" -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo -DLINUX_32BIT=OFF \
    -DCMAKE_C_COMPILER=$CC -DCMAKE_CXX_COMPILER=$CXX \
    -DCMAKE_SHARED_LINKER_FLAGS="-static-libstdc++ -static-libgcc -Wl,--exclude-libs,ALL" \
    -DCMAKE_EXE_LINKER_FLAGS="-static-libstdc++ -static-libgcc" \
    -DCR_DEPS_PREFIX="$DEPS" ${CR_GIT_SHA:+-DCR_GIT_SHA=$CR_GIT_SHA}
cmake --build "$WORK/build" -j"$JOBS"
(cd "$WORK/build" && ctest --output-on-failure)

OUT="$SRC/dist64"
mkdir -p "$OUT"
cp "$WORK/build/cloud_redirect.so" "$WORK/build/cloud_redirect_cli" "$OUT/"
x86_64-conda-linux-gnu-strip --strip-unneeded "$OUT/cloud_redirect.so" "$OUT/cloud_redirect_cli"
python3 "$SRC/scripts/check-linux64-abi.py" "$OUT/cloud_redirect.so" --cli "$OUT/cloud_redirect_cli"
(cd "$OUT" && sha256sum cloud_redirect.so cloud_redirect_cli > SHA256SUMS && cat SHA256SUMS)
file "$OUT/cloud_redirect.so"
