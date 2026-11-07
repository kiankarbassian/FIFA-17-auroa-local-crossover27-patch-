#!/bin/zsh
# Audit the original CrossOver 26.3 Wine patch series against a DIFFERENT
# CrossOver Wine source tree. No installed CrossOver app or bottle is touched.
# Usage: /bin/zsh tools/audit-crossover27.zsh /path/to/crossover-sources-27*.tar.gz [report-directory]
# Also accepts an already extracted source directory containing sources/wine,
# wine/, or the Wine tree directly.
set -eu

ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    print -r -- "Usage: /bin/zsh tools/audit-crossover27.zsh <source-tarball-or-directory> [report-directory]"
    print -r -- "This is a source compatibility audit, not a FIFA 17 installer."
    exit 2
fi
SOURCE="$1"
REPORT="$PWD/crossover27-port-report"
[ "$#" -lt 2 ] || REPORT="$2"
if [ ! -f "$SOURCE" ] && [ ! -d "$SOURCE" ]; then
    print -ru2 -- "Source not found: $SOURCE"
    exit 2
fi
mkdir -p "$REPORT"
REPORT="$(cd -- "$REPORT" && pwd)"
TEMP="$(mktemp -d)"
trap 'rm -rf -- "$TEMP"' EXIT

print -r -- "Source: $SOURCE" > "$REPORT/summary.txt"
print -r -- "Audit only: does not alter CrossOver.app or any bottles." >> "$REPORT/summary.txt"
print -r -- "Patch order follows build.sh. Strictly requires each patch to apply without conflict." >> "$REPORT/summary.txt"
print -r -- "" >> "$REPORT/summary.txt"

print -r -- "Preparing a disposable source tree..."
if [ -f "$SOURCE" ]; then
    tar -xzf "$SOURCE" -C "$TEMP" || { print -ru2 -- "Could not unpack source tarball"; exit 2; }
else
    if [ -d "$SOURCE/sources/wine" ]; then
        cp -R "$SOURCE/sources/wine" "$TEMP/wine"
    elif [ -d "$SOURCE/wine" ]; then
        cp -R "$SOURCE/wine" "$TEMP/wine"
    elif [ -d "$SOURCE/dlls" ]; then
        cp -R "$SOURCE" "$TEMP/wine"
    else
        print -ru2 -- "No wine source tree found inside $SOURCE"
        exit 2
    fi
fi

WINE="$TEMP/wine"
[ -d "$WINE" ] || WINE="$TEMP/sources/wine"
[ -d "$WINE/dlls" ] || { print -ru2 -- "No Wine dlls/ directory found in extracted archive"; exit 2; }

# Keep in sync with the order in build.sh; later changes depend on earlier ones.
PATCHES=(
    crossover-26.3-fifa17-rosetta.patch
    crossover-26.3-fifa17-online.patch
    crossover-26.3-fifa17-audio.patch
    crossover-26.3-fifa17-cng.patch
    crossover-26.3-topdown-alloc-limit.patch
    crossover-26.3-gdiplus-delete-font-collection.patch
    crossover-26.3-ole32-revoke-foreign-window.patch
    crossover-26.3-win32u-shm-flush-under-user-lock.patch
    crossover-26.3-debug-register-emulation.patch
    crossover-26.3-pf-pae-enabled.patch
    crossover-26.3-fifa16-dst-complement.patch
    crossover-26.3-drtrap-syscall-stub.patch
    crossover-26.3-game-profiles.patch
    crossover-26.3-fifa17-folder-gate.patch
    crossover-26.3-remote-thread-exit.patch
    crossover-26.3-aurora-elevate.patch
)

passed=0
skipped=0
for p in $PATCHES; do
    file="$ROOT/patches/$p"
    if [ ! -f "$file" ]; then
        print -r -- "SKIP  $p (not included in this checkout)" | tee -a "$REPORT/summary.txt"
        skipped=$((skipped + 1))
        continue
    fi
    log="$REPORT/$p.log"
    if ( cd "$WINE" && patch -p1 --dry-run --forward --silent < "$file" ) > "$log" 2>&1; then
        if ( cd "$WINE" && patch -p1 --forward --silent < "$file" ) >> "$log" 2>&1; then
            print -r -- "PASS  $p" | tee -a "$REPORT/summary.txt"
            passed=$((passed + 1))
        else
            print -r -- "FAIL  $p (dry run passed but actual application failed)" | tee -a "$REPORT/summary.txt"
            print -r -- "Log: $log"
            exit 1
        fi
    elif ( cd "$WINE" && patch -p1 --dry-run --reverse --silent < "$file" ) > "$log" 2>&1; then
        print -r -- "ALREADY APPLIED  $p" | tee -a "$REPORT/summary.txt"
        passed=$((passed + 1))
    else
        print -r -- "CONFLICT  $p" | tee -a "$REPORT/summary.txt"
        print -r -- "First incompatible patch found. Later patches may depend on it." | tee -a "$REPORT/summary.txt"
        print -r -- "Review: $log"
        exit 1
    fi
done
print -r -- "All available patches applied to the disposable source tree ($passed passed, $skipped absent)." | tee -a "$REPORT/summary.txt"
print -r -- "This does NOT prove binary or gameplay compatibility: compilation, ABI review and game testing remain." | tee -a "$REPORT/summary.txt"
