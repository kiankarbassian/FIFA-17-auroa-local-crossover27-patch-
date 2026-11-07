#!/bin/sh
# Build the minimal FIFA 17 Wine 11.17 modules for CrossOver 27 Preview 20261015.
# This script NEVER modifies CrossOver.app, a bottle, or the original source tarball.
#   sh tools/build-crossover27-minimal.sh --check
#   sh tools/build-crossover27-minimal.sh ~/Downloads/wine-source-crossover-preview-20261015.tar.xz
# Output: crossover27-build/ (entirely separate, no automatic installation)
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
EXPECTED_NAME=wine-source-crossover-preview-20261015.tar.xz
EXPECTED_SHA256=964f820cf6438f1b256fa66b78a6a4f0144a76c854fbf4bdc9ad422bbf094dc7
MIN_MACOS=14.0

fail() { printf '\nSTOP: %s\n' "$*" >&2; exit 1; }
say() { printf '%s\n' "$*"; }

# llvm-mingw can be installed outside PATH. Use an explicit override when needed.
if [ -n "${LLVM_MINGW:-}" ]; then
    PATH="$LLVM_MINGW/bin:$PATH"
elif [ -x "$HOME/.local/cxge/toolchains/llvm-mingw/bin/x86_64-w64-mingw32-clang" ]; then
    PATH="$HOME/.local/cxge/toolchains/llvm-mingw/bin:$PATH"
fi
if command -v brew >/dev/null 2>&1; then
    BREW_BISON="$(brew --prefix bison 2>/dev/null || true)"
    [ -z "$BREW_BISON" ] || PATH="$BREW_BISON/bin:$PATH"
fi
export PATH

prereqs() {
    [ "$(uname -s)" = "Darwin" ] || fail "Run this on your Mac."
    command -v xcrun >/dev/null 2>&1 || fail "Install Xcode command line tools: xcode-select --install"
    command -v x86_64-w64-mingw32-clang >/dev/null 2>&1 ||
        command -v x86_64-w64-mingw32-gcc >/dev/null 2>&1 ||
        fail "A mingw-w64 x86_64 compiler is required. Install llvm-mingw or brew install mingw-w64."
    command -v bison >/dev/null 2>&1 || fail "Install Homebrew bison: brew install bison"
    bison --version | head -1
    BISON_MAJOR=$(bison --version | head -1 | sed 's/.* //;s/\..*//')
    case "$BISON_MAJOR" in ''|*[!0-9]*) fail "Cannot determine bison version" ;; esac
    [ "$BISON_MAJOR" -ge 3 ] || fail "Apple's bison is too old. Install brew install bison."
    command -v patch >/dev/null 2>&1 || fail "Missing patch tool"
    command -v make >/dev/null 2>&1 || fail "Missing make"
    command -v lipo >/dev/null 2>&1 || fail "Missing lipo"
    command -v otool >/dev/null 2>&1 || fail "Missing otool"
    SDKROOT=$(xcrun --show-sdk-path) || fail "No active macOS SDK"
    [ -d "$SDKROOT" ] || fail "macOS SDK path is not a directory: $SDKROOT"
    export SDKROOT
    GNUTLS_INCLUDE=""
    if command -v brew >/dev/null 2>&1; then
        GNUTLS_PREFIX=$(brew --prefix gnutls 2>/dev/null || true)
        [ -z "$GNUTLS_PREFIX" ] || GNUTLS_INCLUDE="$GNUTLS_PREFIX/include"
    fi
    if [ ! -d "$GNUTLS_INCLUDE/gnutls" ]; then
        if [ -d /opt/homebrew/include/gnutls ]; then GNUTLS_INCLUDE=/opt/homebrew/include
        elif [ -d /usr/local/include/gnutls ]; then GNUTLS_INCLUDE=/usr/local/include
        else fail "Install GnuTLS headers: brew install gnutls"; fi
    fi
    export GNUTLS_INCLUDE
    TEMP_PROBE=$(mktemp -d) || fail "Cannot create temporary compiler probe"
    printf '%s\n' 'int cx27_probe(void) { return 1; }' > "$TEMP_PROBE/probe.c"
    if ! /usr/bin/clang -arch x86_64 "-isysroot" "$SDKROOT" \
        "-mmacosx-version-min=$MIN_MACOS" -dynamiclib \
        "$TEMP_PROBE/probe.c" -o "$TEMP_PROBE/probe.dylib" 2>"$TEMP_PROBE/error"; then
        cat "$TEMP_PROBE/error" >&2
        rm -rf "$TEMP_PROBE"
        fail "Could not link an x86_64 dynamic library."
    fi
    PROBE_ARCH=$(lipo -archs "$TEMP_PROBE/probe.dylib" 2>/dev/null || true)
    rm -rf "$TEMP_PROBE"
    [ "$PROBE_ARCH" = "x86_64" ] || fail "Clang produced $PROBE_ARCH instead of x86_64."
    say "PASS: Xcode SDK, x86_64 linker, mingw-w64, bison and GnuTLS headers."
    say "This checks prerequisites only; it does not confirm a Wine build."
}

if [ "${1:-}" = "--check" ]; then
    [ "$#" -eq 1 ] || fail "Usage: $0 --check"
    prereqs
    exit 0
fi
[ "$#" -ge 1 ] && [ "$#" -le 2 ] ||
    fail "Usage: $0 /path/to/$EXPECTED_NAME [new-output-directory]"
SOURCE=$1
[ -f "$SOURCE" ] || fail "Archive not found: $SOURCE"
[ "$(basename "$SOURCE")" = "$EXPECTED_NAME" ] ||
    fail "Use exactly $EXPECTED_NAME (CrossOver Preview 20261015)."
ACTUAL_SHA256=$(shasum -a 256 "$SOURCE" | awk '{print $1}')
[ "$ACTUAL_SHA256" = "$EXPECTED_SHA256" ] ||
    fail "CrossOver 27 source SHA-256 mismatch. Refusing an unknown build."
prereqs

OUT=${2:-"$ROOT/crossover27-build"}
case "$OUT" in *' '*) fail "Wine build paths cannot contain spaces: $OUT" ;; esac
[ ! -e "$OUT" ] || fail "Output already exists: $OUT. Choose a new output path; never overwrite old build results."
mkdir -p "$OUT/source" "$OUT/build" "$OUT/logs" "$OUT/payload/x86_64-unix" "$OUT/payload/x86_64-windows"
OUT=$(CDPATH= cd "$OUT" && pwd)
say "Unpacking verified CrossOver Preview Wine sources into $OUT/source"
tar -xf "$SOURCE" -C "$OUT/source" || fail "Could not unpack source archive."

WINE=""
for candidate in "$OUT/source/wine" "$OUT/source/sources/wine" "$OUT/source"; do
    if [ -f "$candidate/configure" ] && [ -d "$candidate/dlls" ]; then
        WINE=$candidate
        break
    fi
done
[ -n "$WINE" ] || fail "Expected Wine source directory not found after unpacking."
[ -f "$WINE/VERSION" ] || fail "Missing Wine VERSION file."
grep -Fq "11.17" "$WINE/VERSION" || fail "Source VERSION is not Wine 11.17."
say "Applying exactly four patches to the isolated source tree"
for p in \
    crossover-27-fifa17-rosetta.patch \
    crossover-27-fifa17-online.patch \
    crossover-27-fifa17-audio.patch \
    crossover-27-fifa17-cng-minimal.patch
do
    file="$ROOT/patches/$p"
    [ -f "$file" ] || fail "Missing patch: $file"
    if ! (cd "$WINE" && patch -p1 --dry-run --forward --batch --fuzz=0 < "$file") > "$OUT/logs/$p.log" 2>&1; then
        tail -25 "$OUT/logs/$p.log" >&2
        fail "Patch did not apply: $p"
    fi
    if ! (cd "$WINE" && patch -p1 --forward --batch --fuzz=0 < "$file") >> "$OUT/logs/$p.log" 2>&1; then
        fail "Patch application failed unexpectedly: $p"
    fi
    say "PASS $p"
done

say "Configuring Wine 11.17 for the x86_64 CrossOver engine (log: $OUT/logs/configure.log)"
CC="/usr/bin/clang -arch x86_64 -isysroot $SDKROOT -mmacosx-version-min=$MIN_MACOS"
CXX="/usr/bin/clang++ -arch x86_64 -isysroot $SDKROOT -mmacosx-version-min=$MIN_MACOS"
export CC CXX
if ! (cd "$OUT/build" &&
    CC="$CC" CXX="$CXX" \
    LDFLAGS="-isysroot $SDKROOT -mmacosx-version-min=$MIN_MACOS" \
    "$WINE/configure" --host=x86_64-apple-darwin --enable-archs=x86_64 \
    --without-freetype --without-x --without-gstreamer --without-vulkan --without-opengl \
    --without-cups --without-dbus --without-fontconfig --without-gnutls \
    --without-krb5 --without-gssapi --without-opencl --without-pcap \
    --without-usb --without-v4l2 --without-sane --without-gphoto \
    --without-netapi --without-pulse --without-alsa --without-oss --without-udev \
    --without-unwind --without-ffmpeg --without-inotify \
    ac_cv_func_pipe2=no
) > "$OUT/logs/configure.log" 2>&1; then
    tail -30 "$OUT/logs/configure.log" >&2
    fail "Wine configure failed. Full log: $OUT/logs/configure.log"
fi

# As in the working 26.3 project, force the GnuTLS Unix cryptography
# implementation even when the build host has only arm64 GnuTLS libraries.
# The real libgnutls.30.dylib is loaded by name at runtime from CrossOver.
CONFIG="$OUT/build/include/config.h"
[ -f "$CONFIG" ] || fail "Wine configuration header missing."
if ! grep -q '^#define SONAME_LIBGNUTLS' "$CONFIG"; then
    grep -Fq '/* #undef SONAME_LIBGNUTLS */' "$CONFIG" ||
        fail "Unexpected GnuTLS configure state; cannot safely enable the Unix implementation."
    sed -i '' 's|/\* #undef SONAME_LIBGNUTLS \*/|#define SONAME_LIBGNUTLS "libgnutls.30.dylib"|' "$CONFIG"
fi
grep -q '^#define SONAME_LIBGNUTLS' "$CONFIG" || fail "GnuTLS Unix implementation is still disabled."
[ ! -e "$OUT/build/include/gnutls" ] ||
    fail "Unexpected existing GnuTLS include path; refusing to replace it."
ln -s "$GNUTLS_INCLUDE/gnutls" "$OUT/build/include/gnutls"

say "Compiling targeted Wine modules (log: $OUT/logs/make.log)"
JOBS=${JOBS:-4}
case "$JOBS" in ''|*[!0-9]*) fail "JOBS must be a positive integer" ;; esac
[ "$JOBS" -gt 0 ] || fail "JOBS must be greater than zero"
if ! (cd "$OUT/build" && make -j"$JOBS" \
    dlls/ntdll/all dlls/version/all dlls/crypt32/all \
    dlls/secur32/all dlls/winecoreaudio.drv/all
) > "$OUT/logs/make.log" 2>&1; then
    tail -45 "$OUT/logs/make.log" >&2
    fail "Compilation failed. Full log: $OUT/logs/make.log"
fi

copy_module() {
    subdir=$1
    name=$2
    target=$3
    candidate="$OUT/build/dlls/$subdir/$name"
    if [ ! -f "$candidate" ]; then
        candidate="$OUT/build/dlls/$subdir/x86_64-windows/$name"
    fi
    [ -f "$candidate" ] || fail "Missing compiled module $subdir/$name; check make.log."
    cp "$candidate" "$OUT/payload/$target/$name"
    if [ "$target" = x86_64-unix ]; then
        ARCH=$(lipo -archs "$OUT/payload/$target/$name" 2>/dev/null || true)
        [ "$ARCH" = x86_64 ] || fail "$name is '$ARCH', not x86_64."
        otool -L "$OUT/payload/$target/$name" > "$OUT/logs/$name-linked-libraries.txt"
    else
        file "$OUT/payload/$target/$name" | grep -Eq 'PE32\+' ||
            fail "$name does not appear to be a 64-bit Windows PE DLL."
    fi
    say "Collected $target/$name"
}
copy_module ntdll ntdll.so x86_64-unix
copy_module crypt32 crypt32.so x86_64-unix
copy_module winecoreaudio.drv winecoreaudio.so x86_64-unix
copy_module version version.dll x86_64-windows
copy_module crypt32 crypt32.dll x86_64-windows
copy_module secur32 secur32.dll x86_64-windows

(cd "$OUT/payload" && shasum -a 256 x86_64-unix/*.so x86_64-windows/*.dll) > "$OUT/payload/SHA256SUMS"
say "Source: Wine 11.17 CrossOver Preview 20261015"
say "Build output: $OUT/payload"
say "SUCCESS: all six module files built and checked for their expected architectures."
say "NOT INSTALLED: do not copy these files into CrossOver before ABI and runtime review."
