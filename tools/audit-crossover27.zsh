#!/bin/zsh
# Audit the original CrossOver 26.3 Wine patch series against a DIFFERENT
# CrossOver Wine source tree. No installed CrossOver app or bottle is touched.
# Usage: /bin/zsh tools/audit-crossover27.zsh /path/to/wine-source-crossover-preview-20261015.tar.xz [report-directory]
# Also accepts an already extracted source directory containing sources/wine,
# wine/, or the Wine tree directly.
set -eu

TARGET_BUILD='27.0.0.41073'
TARGET_SOURCE='crossover-sources-20261015.tar.gz'
PUBLIC_SOURCE='wine-source-crossover-preview-20261015.tar.xz'
PUBLIC_SHA256='964f820cf6438f1b256fa66b78a6a4f0144a76c854fbf4bdc9ad422bbf094dc7'
TARGET_WINE='11.17'

ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    print -r -- "Usage: /bin/zsh tools/audit-crossover27.zsh <source-tarball-or-directory> [report-directory]"
    print -r -- "Target: CrossOver Preview $TARGET_BUILD (Wine $TARGET_WINE). This is not an installer."
    print -r -- "Accepted source archives: $PUBLIC_SOURCE or $TARGET_SOURCE"
    exit 2
fi
SOURCE="$1"
REPORT="$PWD/crossover27-port-report"
[ "$#" -lt 2 ] || REPORT="$2"
if [ ! -f "$SOURCE" ] && [ ! -d "$SOURCE" ]; then
    print -ru2 -- "Source not found: $SOURCE"
    exit 2
fi
if [ -f "$SOURCE" ]; then
    archive_name="${SOURCE:t}"
    case "$archive_name" in
        "$TARGET_SOURCE") ;;
        "$PUBLIC_SOURCE")
            got_sha="$(shasum -a 256 "$SOURCE" | awk '{print $1}')"
            if [ "$got_sha" != "$PUBLIC_SHA256" ]; then
                print -ru2 -- "SHA-256 mismatch for $PUBLIC_SOURCE"
                print -ru2 -- "Expected $PUBLIC_SHA256"
                print -ru2 -- "Actual   $got_sha"
                print -ru2 -- "Source archive was not modified or extracted."
                exit 2
            fi ;;
        *)
            print -ru2 -- "Wrong source archive: $archive_name"
            print -ru2 -- "Expected $TARGET_SOURCE or $PUBLIC_SOURCE for CrossOver Preview $TARGET_BUILD."
            exit 2 ;;
    esac
fi
mkdir -p "$REPORT"
REPORT="$(cd -- "$REPORT" && pwd)"
TEMP="$(mktemp -d)"
trap 'rm -rf -- "$TEMP"' EXIT

print -r -- "CrossOver target: $TARGET_BUILD; Wine target: $TARGET_WINE" > "$REPORT/summary.txt"
print -r -- "Expected source archive: $TARGET_SOURCE or $PUBLIC_SOURCE" >> "$REPORT/summary.txt"
print -r -- "Source: $SOURCE" >> "$REPORT/summary.txt"
print -r -- "Audit only: does not alter CrossOver.app or any bottles." >> "$REPORT/summary.txt"
[ -f "$SOURCE" ] || print -r -- "WARNING: Directory source supplied; release provenance must be checked separately." >> "$REPORT/summary.txt"
print -r -- "Patch order follows build.sh. Strictly requires each patch to apply without conflict." >> "$REPORT/summary.txt"
print -r -- "" >> "$REPORT/summary.txt"

print -r -- "Preparing a disposable source tree..."
if [ -f "$SOURCE" ]; then
    tar -xf "$SOURCE" -C "$TEMP" || { print -ru2 -- "Could not unpack source tarball"; exit 2; }
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

WINE=""
for candidate in "$TEMP/wine" "$TEMP/sources/wine" "$TEMP"; do
    if [ -d "$candidate/dlls" ]; then
        WINE="$candidate"
        break
    fi
done
if [ -z "$WINE" ]; then
    dlls_dir="$(find "$TEMP" -maxdepth 4 -type d -name dlls -print -quit)"
    [ -z "$dlls_dir" ] || WINE="${dlls_dir:h}"
fi
[ -n "$WINE" ] && [ -d "$WINE/dlls" ] || { print -ru2 -- "No Wine dlls/ directory found in extracted archive"; exit 2; }

wine_version=""
if [ -f "$WINE/VERSION" ]; then
    wine_version="$(cat "$WINE/VERSION")"
    print -r -- "Wine VERSION: $wine_version" >> "$REPORT/summary.txt"
fi
if [ -z "$wine_version" ] && [ -f "$WINE/configure.ac" ]; then
    wine_version="$(grep -m 1 'AC_INIT' "$WINE/configure.ac" || true)"
    print -r -- "Wine configure identifier: $wine_version" >> "$REPORT/summary.txt"
fi
if ! print -r -- "$wine_version" | grep -Fq -- "$TARGET_WINE"; then
    print -ru2 -- "Source does not identify Wine $TARGET_WINE."
    print -ru2 -- "Check archive build and $REPORT/summary.txt."
    exit 2
fi

# Keep in sync with the order in build.sh; later changes depend on earlier ones.
PATCHES=(
    crossover-27-fifa17-rosetta.patch
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
    if ( cd "$WINE" && patch -p1 --dry-run --forward --batch --fuzz=0 < "$file" ) > "$log" 2>&1; then
        if ( cd "$WINE" && patch -p1 --forward --batch --fuzz=0 < "$file" ) >> "$log" 2>&1; then
            print -r -- "PASS  $p" | tee -a "$REPORT/summary.txt"
            passed=$((passed + 1))
        else
            print -r -- "FAIL  $p (dry run passed but actual application failed)" | tee -a "$REPORT/summary.txt"
            print -r -- "Log: $log"
            exit 1
        fi
    elif ( cd "$WINE" && patch -p1 --dry-run --reverse --batch --fuzz=0 < "$file" ) > "$log" 2>&1; then
        print -r -- "ALREADY APPLIED  $p" | tee -a "$REPORT/summary.txt"
        passed=$((passed + 1))
    else
        print -r -- "CONFLICT  $p" | tee -a "$REPORT/summary.txt"
        print -r -- "First incompatible patch found (no fuzz accepted). Later patches may depend on it." | tee -a "$REPORT/summary.txt"
        print -r -- "Review: $log"
        exit 1
    fi
done
print -r -- "All available patches applied to the disposable source tree ($passed passed, $skipped absent)." | tee -a "$REPORT/summary.txt"
print -r -- "This does NOT prove binary or gameplay compatibility: compilation, ABI review and game testing remain." | tee -a "$REPORT/summary.txt"
