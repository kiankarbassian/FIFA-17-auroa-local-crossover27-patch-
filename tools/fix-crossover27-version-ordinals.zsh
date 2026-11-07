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
SPEC="$(find "$SOURCE" -maxdepth 8 -type f -path "*/dlls/version/version.spec" -print -quit)"
[ -f "$SPEC" ] || fail "No version.spec in previously extracted Wine source."
STOCK_PE="$OUT/abi-report/x86_64-windows_version.dll.stock.pe.txt"
[ -f "$STOCK_PE" ] || fail "Original version.dll ABI report missing; cannot confirm preserved ordinals."
WINE="${SPEC%/dlls/version/version.spec}"
grep -Fq "11.17" "$WINE/VERSION" || fail "Unexpected Wine version; nothing changed."

BACKUP_SPEC="$LOGS/version.spec.pre-ordinal-fix"
BACKUP_DLL="$LOGS/version.dll.pre-ordinal-fix"
BACKUP_HASH="$LOGS/SHA256SUMS.pre-ordinal-fix"
if [ -e "$BACKUP_SPEC" ] || [ -e "$BACKUP_DLL" ] || [ -e "$BACKUP_HASH" ]; then
    # Earlier script stopped after editing the new helper, but before
    # compiling. Resume without overwriting its original file backups.
    [ -f "$BACKUP_SPEC" ] && [ -f "$BACKUP_DLL" ] && [ -f "$BACKUP_HASH" ] ||
        fail "Incomplete original backups; inspect the files under $LOGS before continuing."
    grep -Fqx -- "$OLD" "$BACKUP_SPEC" &&
        grep -Fqx -- "$OLD_FIRST" "$BACKUP_SPEC" ||
        fail "Backed-up original spec is not the expected initial source."
    cmp -s "$BACKUP_DLL" "$PAYLOAD/x86_64-windows/version.dll" &&
        cmp -s "$BACKUP_HASH" "$PAYLOAD/SHA256SUMS" ||
        fail "The payload changed since the backups; refusing to overwrite another build."
    # Only the two expected lines may differ in the working spec.
    if ! { grep -Fqx -- "$OLD_FIRST" "$SPEC" || grep -Fqx -- "$NEW_FIRST" "$SPEC"; }; then
        fail "Unexpected first-export state in version.spec; inspect before continuing."
    fi
    if ! { grep -Fqx -- "$OLD" "$SPEC" || grep -Fqx -- "$NEW" "$SPEC"; }; then
        fail "Unexpected helper-export state in version.spec; inspect before continuing."
    fi
    print -r -- "Resuming the interrupted ordinal repair; original backups preserved."
else
    grep -Fqx -- "$OLD" "$SPEC" || fail "Expected original helper not found in version.spec."
    grep -Fqx -- "$OLD_FIRST" "$SPEC" || fail "Expected original first export not found in version.spec."
    cp "$SPEC" "$BACKUP_SPEC"
    cp "$PAYLOAD/x86_64-windows/version.dll" "$BACKUP_DLL"
    cp "$PAYLOAD/SHA256SUMS" "$BACKUP_HASH"
fi

# The first export has '-import' in the Wine 11.17 .spec. The previous
# script omitted this token and silently failed to replace the line.
if grep -Fqx -- "$OLD_FIRST" "$SPEC"; then
    sed -i "" "s|^@ stdcall -import GetFileVersionInfoA(str long long ptr)$|1 stdcall -import GetFileVersionInfoA(str long long ptr)|" "$SPEC"
fi
if grep -Fqx -- "$OLD" "$SPEC"; then
    sed -i "" "s|^@ stdcall GetFileVersionInfoByHandle(ptr wstr long ptr)$|17 stdcall GetFileVersionInfoByHandle(ptr wstr long ptr)|" "$SPEC"
fi
grep -Fqx -- "$NEW_FIRST" "$SPEC" && grep -Fqx -- "$NEW" "$SPEC" ||
    fail "Could not pin both ordinals. The original version.spec is preserved in $BACKUP_SPEC."
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
