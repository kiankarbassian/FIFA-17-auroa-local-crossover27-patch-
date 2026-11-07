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
grep -Fqx -- "$OLD" "$SPEC" || fail "Expected original version.spec line not found; nothing changed."
WINE="${SPEC%/dlls/version/version.spec}"
grep -Fq "11.17" "$WINE/VERSION" || fail "Unexpected Wine version; nothing changed."
cp "$SPEC" "$LOGS/version.spec.pre-ordinal-fix"
cp "$PAYLOAD/x86_64-windows/version.dll" "$LOGS/version.dll.pre-ordinal-fix"
cp "$PAYLOAD/SHA256SUMS" "$LOGS/SHA256SUMS.pre-ordinal-fix"
sed -i "" "s|^@ stdcall GetFileVersionInfoByHandle(ptr wstr long ptr)$|17 stdcall GetFileVersionInfoByHandle(ptr wstr long ptr)|" "$SPEC"
grep -Fqx -- "$NEW" "$SPEC" || fail "Could not change the helper ordinal; original spec backed up in logs."
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
# Match original, fixed export ordinals and names. This checks the 16 old
# ordinal-to-name mappings, not just presence of function names.
get_exports() {
    sed -nE 's/.*\+base\[[[:space:]]*([0-9]+)\][[:space:]]+[[:xdigit:]]+[[:space:]]+([^[:space:]]+).*/\1 \2/p' "$1" | LC_ALL=C sort -k1,1n
}
get_exports "$OUT_PE" > "$LOGS/version.dll-ordinal-new-map.txt"
[ "$(wc -l < "$LOGS/version.dll-ordinal-new-map.txt" | tr -d " ")" -eq 17 ] || fail "Rebuilt DLL has an unexpected export count; original payload unchanged."
grep -Fxq "17 GetFileVersionInfoByHandle" "$LOGS/version.dll-ordinal-new-map.txt" || fail "New function did not get ordinal 17; original payload unchanged."
# Stock ordinal list: the original preview version.dll is accessible via the
# app located by the ABI report tool. Build the deterministic baseline from
# the Wine 11.17 version.spec before the patch (16 original exports).
EXPECTED="$LOGS/version.dll-ordinal-expected-map.txt"
awk '$1 == "@" && $2 == "stdcall" { f=$3; sub(/\(.*/, "", f); print ++n " " f }' "$WINE/dlls/version/version.spec" >/dev/null 2>&1 || true
# Use the Wine source from our initial backup: the inserted helper was the
# second line. The remaining 16 exports are in their original order.
awk '$1 == "@" && $2 == "stdcall" { function_name=$3; sub(/\(.*/, "", function_name); print ++n " " function_name }' "$LOGS/version.spec.pre-ordinal-fix" | LC_ALL=C sort -k1,1n > "$EXPECTED"
[ "$(wc -l < "$EXPECTED" | tr -d " ")" -eq 17 ] || fail "Could not reconstruct original export list; original payload unchanged."
# Remove added helper and shift subsequent old ordinals back one.
awk '$2 != "GetFileVersionInfoByHandle" {num=$1; if (num>1) num--; print num " " $2}' "$EXPECTED" > "$LOGS/version.dll-ordinal-stock-map.txt"
while IFS= read -r expected; do
    grep -Fxq "$expected" "$LOGS/version.dll-ordinal-new-map.txt" || fail "Original export ordinal changed: $expected. Original payload unchanged."
done < "$LOGS/version.dll-ordinal-stock-map.txt"
cp "$NEW_DLL" "$PAYLOAD/x86_64-windows/version.dll"
(cd "$PAYLOAD" && shasum -a 256 x86_64-unix/*.so x86_64-windows/*.dll) > "$PAYLOAD/SHA256SUMS"
(cd "$PAYLOAD" && shasum -a 256 -c SHA256SUMS >/dev/null) || fail "Updated payload SHA256SUMS failed."
print -r -- "PASS: New version.dll export GetFileVersionInfoByHandle is ordinal 17."
print -r -- "PASS: All 16 pre-existing version.dll exports retain their original ordinals."
print -r -- "PASS: Rebuilt version.dll copied to disposable payload and checksum manifest updated."
print -r -- "No installed CrossOver app or bottle was changed."
