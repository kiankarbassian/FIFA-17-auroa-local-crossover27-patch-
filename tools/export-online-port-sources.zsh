#!/bin/zsh
# Export the two Wine 11.17 source files needed to rebase FIFA 17's online patch.
# This never writes to CrossOver.app, any bottle, or the extracted game.
set -eu

ARCHIVE="${1:-$HOME/Downloads/wine-source-crossover-preview-20261015.tar.xz}"
OUT="${2:-$HOME/Desktop/fifa17-crossover27-online-sources}"
EXPECTED_SHA256="964f820cf6438f1b256fa66b78a6a4f0144a76c854fbf4bdc9ad422bbf094dc7"

if [ ! -f "$ARCHIVE" ]; then
    print -ru2 -- "Source archive not found: $ARCHIVE"
    exit 2
fi

case "${ARCHIVE:t}" in
    wine-source-crossover-preview-20261015.tar.xz)
        actual_sha="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
        if [ "$actual_sha" != "$EXPECTED_SHA256" ]; then
            print -ru2 -- "SHA-256 mismatch: refusing to extract unexpected source archive."
            exit 2
        fi ;;
    *)
        print -ru2 -- "Expected wine-source-crossover-preview-20261015.tar.xz"
        exit 2 ;;
esac

mkdir -p "$OUT"
OUT="$(cd -- "$OUT" && pwd)"

# Match archive entries regardless of whether they start with ./, wine/ or sources/wine/.
for record in "schannel.c:dlls/secur32/schannel.c" "pfx.c:dlls/crypt32/pfx.c"; do
    name="${record%%:*}"
    relative="${record#*:}"
    entry="$(tar -tf "$ARCHIVE" | grep -E "(^|/)${relative//./\\.}$" | head -n 1 || true)"
    if [ -z "$entry" ]; then
        print -ru2 -- "Could not locate $relative in the archive."
        exit 2
    fi
    tar -xOf "$ARCHIVE" "$entry" > "$OUT/$name"
    if [ ! -s "$OUT/$name" ]; then
        print -ru2 -- "Failed to extract $name"
        exit 2
    fi
    print -r -- "Exported $OUT/$name"
done
print -r -- "Upload both files to the conversation; do not upload the full 50 MB source archive."
