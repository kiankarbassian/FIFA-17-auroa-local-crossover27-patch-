#!/bin/zsh
# Export only the CrossOver Preview 20261015 audio sources needed for a
# source-level rebase. Does not touch an installed CrossOver app or bottle.
set -eu

ARCHIVE="${1:-$HOME/Downloads/wine-source-crossover-preview-20261015.tar.xz}"
OUT="${2:-$HOME/Desktop/fifa17-crossover27-audio-sources}"
EXPECTED_SHA256="964f820cf6438f1b256fa66b78a6a4f0144a76c854fbf4bdc9ad422bbf094dc7"

if [ ! -f "$ARCHIVE" ]; then
    print -ru2 -- "Source archive not found: $ARCHIVE"
    exit 2
fi
if [ "${ARCHIVE:t}" != "wine-source-crossover-preview-20261015.tar.xz" ]; then
    print -ru2 -- "Expected the Wine source for CrossOver Preview 20261015."
    exit 2
fi
actual="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
if [ "$actual" != "$EXPECTED_SHA256" ]; then
    print -ru2 -- "SHA-256 mismatch for CrossOver Preview 20261015 archive."
    exit 2
fi

mkdir -p "$OUT"
OUT="$(cd -- "$OUT" && pwd)"

for source in \
    "coreaudio.c:dlls/winecoreaudio.drv/coreaudio.c" \
    "authorization.m:dlls/winecoreaudio.drv/authorization.m"
do
    name="${source%%:*}"
    relative="${source#*:}"
    # The release archive may place Wine sources under an enclosing directory.
    entry="$(tar -tf "$ARCHIVE" | grep -F "/$relative" | head -n 1 || true)"
    if [ -z "$entry" ]; then
        entry="$(tar -tf "$ARCHIVE" | grep -F "$relative" | head -n 1 || true)"
    fi
    if [ -z "$entry" ] || [ "${entry:t}" != "$name" ]; then
        print -ru2 -- "Could not find the expected $relative in the archive."
        exit 2
    fi
    tar -xOf "$ARCHIVE" "$entry" > "$OUT/$name"
    if [ ! -s "$OUT/$name" ]; then
        print -ru2 -- "Could not extract $name."
        exit 2
    fi
    print -r -- "Exported $OUT/$name"
done
print -r -- "Please upload coreaudio.c and authorization.m from $OUT."
