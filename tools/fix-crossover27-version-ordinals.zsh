#!/bin/zsh
# One-time incremental rebuild for version.dll's new helper export.
# Fixes shifted version.dll ordinals without rebuilding all six Wine modules.
# This edits ONLY the disposable crossover27-build/source and build/payload.
# It never touches installed CrossOver or bottles.
set -eu
ROOT="${0:A:h:h}"
OUT="$ROOT/crossover27-build"
SOURCE="$OUT/source"
BUILD="$OUT/build"
PAYLOAD="$OUT/payload"
LOGS="$OUT/logs"
OLD="@ stdcall GetFileVersionInfoByHandle(ptr wstr long ptr)"
NEW="17 stdcall GetFileVersionInfoByHandle(ptr wstr long ptr)"
OLD_FIRST="@ stdcall -import GetFileVersionInfoA(str long long ptr)"
NEW_FIRST="1 stdcall -import GetFileVersionInfoA(str long long ptr)"
fail() { print -ru2 -- "STOP: $*"; exit 1; }
[ -d "$SOURCE" ] && [ -f "$BUILD/Makefile" ] || fail "Existing successful CrossOver 27 source/build not found."
[ -f "$PAYLOAD/x86_64-windows/version.dll" ] && [ -f "$PAYLOAD/SHA256SUMS" ] || fail "Existing payload or manifest missing."
[ -d "$LOGS" ] || fail "No build logs directory."
[ "$#" -eq 0 ] || fail "No arguments: /bin/zsh tools/fix-crossover27-version-ordinals.zsh"
command -v x86_64-w64-mingw32-objdump >/dev/null || fail "Missing x86_64-w64-mingw32-objdump."
( cd "$PAYLOAD" && shasum -a 256 -c SHA256SUMS >/dev/null ) || fail "Original payload SHA-256 verification failed."
for oldfile in "$LOGS/version.dll.pre-ordinal-fix" "$LOGS/version.spec.pre-ordinal-fix" "$LOGS/version.dll-ordinal-rebuild.log"; do
    [ ! -e "$oldfile" ] || fail "Previous incremental attempt detected ($oldfile); no files changed."
done
SPEC="$(find "$SOURCE" -maxdepth 8 -type f -path "*/dlls/version/version.spec" -print -quit)"
[ -f "$SPEC" ] || fail "No version.spec in previously extracted Wine source."
grep -Fqx -- "$OLD" "$SPEC" || fail "Expected original version.spec helper not found; nothing changed."
grep -Fqx -- "$OLD_FIRST" "$SPEC" || fail "Expected original version.spec first export not found; nothing changed."
STOCK_PE="$OUT/abi-report/x86_64-windows_version.dll.stock.pe.txt"
[ -f "$STOCK_PE" ] || fail "Read-only ABI report for original version.dll missing; cannot confirm original ordinals."
WINE="${SPEC%/dlls/version/version.spec}"
grep -Fq "11.17" "$WINE/VERSION" || fail "Unexpected Wine version; nothing changed."
cp "$SPEC" "$LOGS/version.spec.pre-ordinal-fix"
cp "$PAYLOAD/x86_64-windows/version.dll" "$LOGS/version.dll.pre-ordinal-fix"
cp "$PAYLOAD/SHA256SUMS" "$LOGS/SHA256SUMS.pre-ordinal-fix"
sed -i "" "s|^@ stdcall GetFileVersionInfoA(str long long ptr)$|1 stdcall GetFileVersionInfoA(str long long ptr)|" "$SPEC"
sed -i "" "s|^@ stdcall GetFileVersionInfoByHandle(ptr wstr long ptr)$|17 stdcall GetFileVersionInfoByHandle(ptr wstr long ptr)|" "$SPEC"
grep -Fqx -- "$NEW_FIRST" "$SPEC" && grep -Fqx -- "$NEW" "$SPEC" || fail "Could not pin both ordinals; original spec backed up in logs."
print -r -- "Rebuilding only version.dll; existing ntdll, crypt32, secur32, audio modules are untouched..."
if ! (cd "$BUILD" && make -j4 dlls/version/all) > "$LOGS/version.dll-ordinal-rebuild.log" 2>&1; then
    tail -35 "$LOGS/version.dll-ordinal-rebuild.log" >&2
    fail "Version DLL incremental rebuild failed. See $LOGS/version.dll-ordinal-rebuild.log"
fi
NEW_DLL="$BUILD/dlls/version/x86_64-windows/version.dll"
[ -f "$NEW_DLL" ] || NEW_DLL="$BUILD/dlls/version/version.dll"
[ -f "$NEW_DLL" ] || fail "Recompiled version.dll not found."
OUT_PE="$LOGS/version.dll-ordinal-new-exports.txt"
x86_64-w64-mingw32-objdump -p "$NEW_DLL" > "$OUT_PE" || fail "Failed to inspect rebuilt version.dll."
# Compare actual ordinal-to-name exports against the stock 41073 DLL,
# not only the symbol names. Only the new helper (ordinal 17) may be added.
get_exports() {
    awk '/^\[Ordinal\/Name Pointer\] Table/ { in_names=1; next }
         in_names && /^$/ { exit }
         in_names { print }' "$1" |
        sed -nE 's/.*\+base\[[[:space:]]*([0-9]+)\][[:space:]]+[[:xdigit:]]+[[:space:]]+([^[:space:]]+).*/\1 \2/p' |
        LC_ALL=C sort -u
}
get_exports "$OUT_PE" > "$LOGS/version.dll-ordinal-new-map.txt"
get_exports "$STOCK_PE" > "$LOGS/version.dll-ordinal-stock-map.txt"
[ "$(wc -l < "$LOGS/version.dll-ordinal-new-map.txt" | tr -d " ")" -eq 17 ] ||
    fail "Rebuilt version.dll has an unexpected export count; original payload unchanged."
[ "$(wc -l < "$LOGS/version.dll-ordinal-stock-map.txt" | tr -d " ")" -eq 16 ] ||
    fail "Original version.dll has an unexpected export count; original payload unchanged."
grep -Fxq "17 GetFileVersionInfoByHandle" "$LOGS/version.dll-ordinal-new-map.txt" ||
    fail "New helper does not have ordinal 17; original payload unchanged."
comm -23 "$LOGS/version.dll-ordinal-stock-map.txt" "$LOGS/version.dll-ordinal-new-map.txt"     > "$LOGS/version.dll-ordinal-mismatch.txt"
[ ! -s "$LOGS/version.dll-ordinal-mismatch.txt" ] ||
    fail "Some existing version.dll export ordinals changed; see $LOGS/version.dll-ordinal-mismatch.txt. Original payload unchanged."
cp "$NEW_DLL" "$PAYLOAD/x86_64-windows/version.dll"
(cd "$PAYLOAD" && shasum -a 256 x86_64-unix/*.so x86_64-windows/*.dll) > "$PAYLOAD/SHA256SUMS"
(cd "$PAYLOAD" && shasum -a 256 -c SHA256SUMS >/dev/null) || fail "Updated payload SHA256SUMS failed."
print -r -- "PASS: New version.dll export GetFileVersionInfoByHandle is ordinal 17."
print -r -- "PASS: All 16 pre-existing version.dll exports retain their original ordinals."
print -r -- "PASS: Rebuilt version.dll copied to disposable payload and checksum manifest updated."
print -r -- "No installed CrossOver app or bottle was changed."
