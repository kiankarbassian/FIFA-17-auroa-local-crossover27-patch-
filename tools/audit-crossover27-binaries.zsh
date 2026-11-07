#!/bin/zsh
# Read-only comparison of the six locally built CrossOver 27 modules with the
# original CrossOver Preview 27.0.0.41073 app. Never installs/signs/runs modules.
# Usage: /bin/zsh tools/audit-crossover27-binaries.zsh [path/to/CrossOver.app]
set -eu
ROOT="${0:A:h:h}"
OUT="$ROOT/crossover27-build"
PAYLOAD="$OUT/payload"
REPORT="$OUT/abi-report"
TARGET_VERSION="27.0.0.41073"
fail() { print -ru2 -- "STOP: $*"; exit 1; }
[ "$#" -le 1 ] || fail "Usage: $0 [path/to/CrossOver Preview.app]"
[ -f "$PAYLOAD/SHA256SUMS" ] || fail "No compiled payload manifest at $PAYLOAD"
( cd "$PAYLOAD" && shasum -a 256 -c SHA256SUMS >/dev/null ) ||
    fail "Built payload SHA256SUMS does not match: do not compare modified files."
get_version() {
    /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$1/Contents/Info.plist" 2>/dev/null || true
}
APP="${1:-}"
if [ -z "$APP" ]; then
    for candidate in /Applications/*CrossOver*.app(N) "$HOME"/Applications/*CrossOver*.app(N); do
        [ "$(get_version "$candidate")" = "$TARGET_VERSION" ] && { APP="$candidate"; break; }
    done
fi
if [ -z "$APP" ]; then
    print -r -- "No CrossOver Preview build $TARGET_VERSION found automatically."
    for candidate in /Applications/*CrossOver*.app(N) "$HOME"/Applications/*CrossOver*.app(N); do
        print -r -- "Available: $candidate ($(get_version "$candidate"))"
    done
    fail "Provide the exact .app path; nothing was modified."
fi
[ -d "$APP" ] || fail "App not found: $APP"
VERSION="$(get_version "$APP")"
[ "$VERSION" = "$TARGET_VERSION" ] || fail "App is build $VERSION, expected $TARGET_VERSION."
BASE="$APP/Contents/SharedSupport/CrossOver/lib/wine"
[ -d "$BASE/x86_64-unix" ] && [ -d "$BASE/x86_64-windows" ] ||
    fail "Expected Wine libraries missing from $APP"
[ ! -e "$REPORT" ] && [ ! -e "$OUT/abi-report.zip" ] ||
    fail "A previous ABI report exists. Save/rename it first; no results overwritten."
mkdir -p "$REPORT"
SUMMARY="$REPORT/summary.txt"
print -r -- "CrossOver 27 / FIFA 17 read-only binary comparison" > "$SUMMARY"
print -r -- "App: $APP (build $VERSION)" >> "$SUMMARY"
print -r -- "Built payload: $PAYLOAD (manifest checked)" >> "$SUMMARY"
print -r -- "" >> "$SUMMARY"

macho_meta() {
    local src="$1" dest="$2"
    file "$src" > "$dest.file.txt"
    lipo -archs "$src" > "$dest.archs.txt" 2>&1 || true
    otool -L "$src" > "$dest.links.txt" 2>&1 || true
    otool -l "$src" > "$dest.loadcommands.txt" 2>&1 || true
    nm -gU "$src" > "$dest.nm.txt" 2>&1 || true
    codesign -dv --verbose=4 "$src" > "$dest.codesign.txt" 2>&1 || true
    awk 'NF>=2 && $NF ~ /^_/ {print $NF}' "$dest.nm.txt" | LC_ALL=C sort -u > "$dest.exports.txt"
    awk 'NR>1 {print $1}' "$dest.links.txt" | LC_ALL=C sort -u > "$dest.libraries.txt"
    awk '$1=="cmd" && $2=="LC_RPATH" {a=1;next} a && $1=="path" {print $2;a=0}' \
        "$dest.loadcommands.txt" | LC_ALL=C sort -u > "$dest.rpaths.txt"
}
for relative in x86_64-unix/ntdll.so x86_64-unix/crypt32.so x86_64-unix/winecoreaudio.so \
    x86_64-windows/version.dll x86_64-windows/crypt32.dll x86_64-windows/secur32.dll; do
    ours="$PAYLOAD/$relative"
    stock="$BASE/$relative"
    [ -f "$ours" ] && [ -f "$stock" ] || fail "Missing built or stock module: $relative"
    name="$(print -r -- "$relative" | tr '/' '_')"
    print -r -- "Comparing $relative"
    print -r -- "=== $relative ===" >> "$SUMMARY"
    if [[ "$relative" == x86_64-unix/* ]]; then
        macho_meta "$stock" "$REPORT/$name.stock"
        macho_meta "$ours" "$REPORT/$name.built"
        a="$(cat "$REPORT/$name.stock.archs.txt")"
        b="$(cat "$REPORT/$name.built.archs.txt")"
        print -r -- "Architecture: stock $a | built $b" >> "$SUMMARY"
        for category in exports libraries rpaths; do
            comm -23 "$REPORT/$name.stock.$category.txt" "$REPORT/$name.built.$category.txt" \
                > "$REPORT/$name.stock-$category-absent-in-build.txt"
            count="$(wc -l < "$REPORT/$name.stock-$category-absent-in-build.txt" | tr -d ' ')"
            print -r -- "$category: $count stock entries absent from built module" >> "$SUMMARY"
        done
        [ -s "$REPORT/$name.stock.exports.txt" ] ||
            print -r -- "NOTE: Stock symbol table missing/stripped; exported symbol check is inconclusive." >> "$SUMMARY"
    else
        file "$ours" > "$REPORT/$name.built.file.txt"
        file "$stock" > "$REPORT/$name.stock.file.txt"
        if command -v x86_64-w64-mingw32-objdump >/dev/null 2>&1; then
            x86_64-w64-mingw32-objdump -p "$stock" > "$REPORT/$name.stock.pe.txt" 2>&1 || true
            x86_64-w64-mingw32-objdump -p "$ours" > "$REPORT/$name.built.pe.txt" 2>&1 || true
            print -r -- "PE import/export headers saved for manual comparison." >> "$SUMMARY"
        else
            print -r -- "PE NOTE: x86_64-w64-mingw32-objdump not on PATH; inspect manually." >> "$SUMMARY"
        fi
    fi
    print -r -- "" >> "$SUMMARY"
done
print -r -- "Review exports, dependencies, rpaths, PE imports/exports, min macOS version and signing before any install." >> "$SUMMARY"
print -r -- "This check does NOT establish runtime ABI or gameplay compatibility." >> "$SUMMARY"
print -r -- "No CrossOver app, bottle or binary was modified, executed, or signed." >> "$SUMMARY"
( cd "$OUT" && zip -q -r abi-report.zip abi-report ) || fail "Could not create text-only report zip."
print -r -- ""
cat "$SUMMARY"
print -r -- ""
print -r -- "Send this text-only report: $OUT/abi-report.zip"
