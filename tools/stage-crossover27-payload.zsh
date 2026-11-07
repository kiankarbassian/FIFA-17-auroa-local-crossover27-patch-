#!/bin/zsh
# Stage an isolated, ad-hoc signed candidate payload for CrossOver Preview 27.
# Never modify installed CrossOver, a bottle or the successful original payload.
# Usage: /bin/zsh tools/stage-crossover27-payload.zsh [CrossOver Preview.app path]
set -eu

ROOT="${0:A:h:h}"
OUT="$ROOT/crossover27-build"
PAYLOAD="$OUT/payload"
STAGE="$OUT/staged-payload"
REPORT="$OUT/abi-report"
PREVIEW="${1:-/Applications/CrossOver Preview.app}"
RELEASE="27.0.0.41073"
REQUIRED_RPATH="@loader_path/../../../lib/x86_64"
fail() { print -ru2 -- "STOP: $*"; exit 1; }
say() { print -r -- "$*"; }

[ "$#" -le 1 ] || fail "Usage: /bin/zsh $0 [CrossOver Preview.app path]"
[ -d "$PREVIEW" ] || fail "CrossOver Preview app not found: $PREVIEW"
ACTUAL=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PREVIEW/Contents/Info.plist" 2>/dev/null || true)
[ "$ACTUAL" = "$RELEASE" ] || fail "Expected CrossOver Preview build $RELEASE; found ${ACTUAL:-unknown}."
CX="$PREVIEW/Contents/SharedSupport/CrossOver"
WINE="$CX/lib/wine"
[ -d "$WINE/x86_64-unix" ] && [ -d "$WINE/x86_64-windows" ] ||
    fail "CrossOver Preview does not contain the expected Wine module paths."
[ -d "$REPORT" ] || fail "Read-only ABI report is missing: $REPORT"
[ -f "$PAYLOAD/SHA256SUMS" ] || fail "Successful build payload missing."
( cd "$PAYLOAD" && shasum -a 256 -c SHA256SUMS >/dev/null ) ||
    fail "Original payload SHA-256 manifest does not match."
[ ! -e "$STAGE" ] || fail "Staged payload already exists; will not overwrite: $STAGE"

# Version export fix must have been validated before packaging.
FIXMAP="$OUT/logs/version.dll-ordinal-new-map.txt"
STOCKMAP="$OUT/logs/version.dll-ordinal-stock-map.txt"
[ -f "$FIXMAP" ] && [ -f "$STOCKMAP" ] ||
    fail "Run tools/fix-crossover27-version-ordinals.zsh before staging."
[ "$(wc -l < "$STOCKMAP" | tr -d ' ')" = 16 ] ||
    fail "Stock version.dll ordinal map does not contain 16 entries."
[ "$(wc -l < "$FIXMAP" | tr -d ' ')" = 17 ] ||
    fail "Rebuilt version.dll ordinal map does not contain 17 entries."
grep -Fxq "17 GetFileVersionInfoByHandle" "$FIXMAP" ||
    fail "New version.dll export was not assigned ordinal 17."
while IFS= read -r entry; do
    grep -Fxq "$entry" "$FIXMAP" ||
        fail "Rebuilt version.dll changed stock ordinal: $entry"
done < "$STOCKMAP"
say "PASS: version.dll old ordinals 1-16 preserved, new helper at 17."

# The CNG PFX path needs this 64-bit GnuTLS dylib at runtime. Because it
# is opened by name with dlopen(), matching otool -L by itself is insufficient.
GNUTLS=""
while IFS= read -r candidate; do
    [ -f "$candidate" ] || continue
    GNUTLS_ARCHS=$(lipo -archs "$candidate" 2>/dev/null || true)
    case " $GNUTLS_ARCHS " in
        *" x86_64 "*) GNUTLS="$candidate"; break ;;
    esac
done < <(find "$CX" -name "libgnutls.30.dylib" -print 2>/dev/null)
[ -n "$GNUTLS" ] ||
    fail "No x86_64 libgnutls.30.dylib found in CrossOver Preview. The CNG PFX import needs that runtime; do not install."
say "PASS: x86_64 GnuTLS runtime: $GNUTLS"

NCRYPT="$WINE/x86_64-windows/ncrypt.dll"
[ -f "$NCRYPT" ] || fail "CrossOver Preview ncrypt.dll missing."
command -v x86_64-w64-mingw32-objdump >/dev/null 2>&1 ||
    fail "mingw-w64 objdump not found; please install/check mingw-w64."
NCRYPT_TEXT=$(x86_64-w64-mingw32-objdump -p "$NCRYPT" 2>/dev/null) ||
    fail "Could not inspect CrossOver Preview ncrypt.dll."
for method in NCryptImportKey NCryptOpenStorageProvider NCryptFreeObject; do
    print -r -- "$NCRYPT_TEXT" | grep -Fq "$method" ||
        fail "Required CNG export not found in CrossOver ncrypt.dll: $method"
done
say "PASS: CrossOver ncrypt.dll supplies the required NCrypt import functions."

mkdir -p "$STAGE/x86_64-unix" "$STAGE/x86_64-windows" "$STAGE/report"
for rel in x86_64-unix/ntdll.so x86_64-unix/crypt32.so \
    x86_64-unix/winecoreaudio.so x86_64-windows/version.dll \
    x86_64-windows/crypt32.dll x86_64-windows/secur32.dll; do
    [ -f "$PAYLOAD/$rel" ] || fail "Missing built module $rel"
    cp "$PAYLOAD/$rel" "$STAGE/$rel"
done

# Compare canonical Mach-O linkage and exports after rpath addition. Only
# the staging copies are modified, and only the copies are ad-hoc signed.
for name in ntdll.so crypt32.so winecoreaudio.so; do
    rel="x86_64-unix/$name"
    stock="$WINE/$rel"
    built="$STAGE/$rel"
    [ -f "$stock" ] || fail "Missing stock module $rel"

    if ! install_name_tool -add_rpath "$REQUIRED_RPATH" "$built" > "$STAGE/report/$name.rpath-edit.log" 2>&1; then
        cat "$STAGE/report/$name.rpath-edit.log" >&2
        fail "Failed to add required CrossOver rpath to staged $name. Installed app untouched."
    fi
    if ! codesign --force --sign - "$built" > "$STAGE/report/$name.sign.log" 2>&1; then
        cat "$STAGE/report/$name.sign.log" >&2
        fail "Could not ad-hoc sign staged $name; installed app untouched."
    fi
    codesign --verify --strict "$built" ||
        fail "Code signature verification failed for staged $name."

    lipo -archs "$built" > "$STAGE/report/$name.arch.txt"
    lipo -archs "$stock" > "$STAGE/report/$name.stock.arch.txt"
    cmp -s "$STAGE/report/$name.arch.txt" "$STAGE/report/$name.stock.arch.txt" ||
        fail "Architecture mismatch in staged $name"

    otool -l "$built" > "$STAGE/report/$name.otool-l.txt"
    awk '$1=="cmd" && $2=="LC_RPATH" {r=1;next} r && $1=="path" {print $2;r=0}' \
        "$STAGE/report/$name.otool-l.txt" > "$STAGE/report/$name.rpaths.txt"
    grep -Fxq "$REQUIRED_RPATH" "$STAGE/report/$name.rpaths.txt" ||
        fail "Required CrossOver rpath is missing after staging: $name"

    otool -L "$built" | awk 'NR>1 {print $1}' | LC_ALL=C sort -u \
        > "$STAGE/report/$name.linked.txt"
    otool -L "$stock" | awk 'NR>1 {print $1}' | LC_ALL=C sort -u \
        > "$STAGE/report/$name.stock-linked.txt"
    cmp -s "$STAGE/report/$name.linked.txt" "$STAGE/report/$name.stock-linked.txt" ||
        fail "Linked-library difference in staged $name"

    nm -gU "$built" | awk 'NF>=2 && $NF ~ /^_/ {print $NF}' | LC_ALL=C sort -u \
        > "$STAGE/report/$name.exports.txt"
    nm -gU "$stock" | awk 'NF>=2 && $NF ~ /^_/ {print $NF}' | LC_ALL=C sort -u \
        > "$STAGE/report/$name.stock-exports.txt"
    cmp -s "$STAGE/report/$name.exports.txt" "$STAGE/report/$name.stock-exports.txt" ||
        fail "Exported-symbol difference in staged $name"

    # Compare deployment targets as well as CPU architecture.
    otool -l "$stock" | awk '/LC_BUILD_VERSION/ {a=1} a && $1=="minos" {print $2;exit}' \
        > "$STAGE/report/$name.stock-minos.txt"
    awk '/LC_BUILD_VERSION/ {a=1} a && $1=="minos" {print $2;exit}' \
        "$STAGE/report/$name.otool-l.txt" > "$STAGE/report/$name.minos.txt"
    cmp -s "$STAGE/report/$name.minos.txt" "$STAGE/report/$name.stock-minos.txt" ||
        fail "Minimum macOS version differs in staged $name"

    say "PASS: $name rpath, ad-hoc signature, architecture, exports, linked libraries and macOS target"
done

(cd "$STAGE" && shasum -a 256 x86_64-unix/*.so x86_64-windows/*.dll) > "$STAGE/SHA256SUMS"
(
  cd "$STAGE"
  shasum -a 256 -c SHA256SUMS >/dev/null
) || fail "Staged payload checksum verification failed."

say ""
say "STAGING COMPLETE: $STAGE"
say "Original build payload and installed CrossOver Preview are untouched."
say "Do not install yet. This is not an application signature or gameplay test."
