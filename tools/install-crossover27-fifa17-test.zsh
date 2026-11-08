#!/bin/zsh
# First isolated FIFA 17 / Aurora17 CrossOver 27 launch preparation.
# This copies CrossOver Preview, installs ONLY the six verified staged modules
# into the copy, signs that copy, and creates a NEW, separate Windows bottle.
# It never changes /Applications/CrossOver Preview.app or an existing bottle.
# Usage: /bin/zsh tools/install-crossover27-fifa17-test.zsh
set -eu
set -o pipefail

ROOT="${0:A:h:h}"
OUT="$ROOT/crossover27-build"
STAGE="$OUT/staged-payload"
ORIGINAL="/Applications/CrossOver Preview.app"
DEST="$HOME/Applications/CrossOver-FIFA17-CX27-Test.app"
BOTTLES="$HOME/Library/Application Support/CrossOver/Bottles"
BOTTLE="FIFA17-CX27-Test"
VERSION="27.0.0.41073"
LOGS="$OUT/test-app-logs"
fail() { print -ru2 -- "STOP: $*"; exit 1; }
say() { print -r -- "$*"; }

[ "$#" -eq 0 ] || fail "No arguments. Usage: /bin/zsh tools/install-crossover27-fifa17-test.zsh"
[ -d "$ORIGINAL" ] || fail "CrossOver Preview not found: $ORIGINAL"
ACTUAL=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$ORIGINAL/Contents/Info.plist" 2>/dev/null || true)
[ "$ACTUAL" = "$VERSION" ] || fail "Wrong Preview version: expected $VERSION, found ${ACTUAL:-unknown}."
[ -d "$STAGE" ] && [ -f "$STAGE/SHA256SUMS" ] || fail "Staged payload missing. Run stage-crossover27-payload.zsh first."
( cd "$STAGE" && shasum -a 256 -c SHA256SUMS >/dev/null ) ||
    fail "Staged payload checksum failed. Nothing was installed."
[ ! -e "$DEST" ] && [ ! -L "$DEST" ] ||
    fail "Test application already exists: $DEST. Never overwrite an existing app."
[ ! -e "$BOTTLES/$BOTTLE" ] && [ ! -L "$BOTTLES/$BOTTLE" ] ||
    fail "Test bottle already exists: $BOTTLES/$BOTTLE. Never overwrite an existing bottle."
# The first installer attempt stopped before copying anything because codesign
# output wasn't converted into an XML plist. Permit ONLY that known failed
# state, preserving both original diagnostic files. Never resume an install
# that got as far as ditto or app signing.
if [ -e "$LOGS" ]; then
    [ -d "$LOGS" ] && [ ! -L "$LOGS" ] ||
        fail "Unexpected test log directory type: $LOGS"
    for item in "$LOGS"/*(N); do
        case "${item:t}" in
            original-entitlements.plist|original-entitlements.failed.raw|read-entitlements.log|read-entitlements.previous.log) ;;
            *) fail "Test logs show another install attempt: $item. Refusing to overwrite anything." ;;
        esac
    done
    if [ -f "$LOGS/original-entitlements.plist" ] &&
       [ -f "$LOGS/read-entitlements.log" ] &&
       [ ! -e "$LOGS/read-entitlements.previous.log" ] &&
       [ ! -e "$LOGS/original-entitlements.failed.raw" ]; then
        mv "$LOGS/original-entitlements.plist" "$LOGS/original-entitlements.failed.raw"
        mv "$LOGS/read-entitlements.log" "$LOGS/read-entitlements.previous.log"
    elif [ -f "$LOGS/read-entitlements.log" ] &&
         [ -f "$LOGS/read-entitlements.previous.log" ] &&
         [ -f "$LOGS/original-entitlements.failed.raw" ] &&
         [ ! -e "$LOGS/original-entitlements.plist" ] &&
         [ ! -e "$LOGS/read-entitlements.second-failure.log" ]; then
        # This is the exact state from the user's second failure: codesign
        # provided zero bytes to plutil and no copy was made.
        mv "$LOGS/read-entitlements.log" "$LOGS/read-entitlements.second-failure.log"
    else
        fail "Existing logs do not match an entitlement-only pre-copy failure; no files were modified."
    fi
    say "Resuming entitlement-only failure; preserved previous diagnostic files."
fi

for rel in x86_64-unix/ntdll.so x86_64-unix/crypt32.so x86_64-unix/winecoreaudio.so \
           x86_64-windows/version.dll x86_64-windows/crypt32.dll x86_64-windows/secur32.dll; do
    [ -f "$STAGE/$rel" ] ||
        fail "Missing staged binary: $rel"
    [ -f "$ORIGINAL/Contents/SharedSupport/CrossOver/lib/wine/$rel" ] ||
        fail "Stock Preview missing a module required for safe replacement: $rel"
done
for so in ntdll.so crypt32.so winecoreaudio.so; do
    codesign --verify --strict "$STAGE/x86_64-unix/$so" >/dev/null 2>&1 ||
        fail "Staged $so has an invalid code signature; rerun staging."
done
command -v ditto >/dev/null || fail "macOS ditto missing"
command -v codesign >/dev/null || fail "macOS codesign missing"
[ -x "$ORIGINAL/Contents/SharedSupport/CrossOver/bin/cxbottle" ] ||
    fail "Preview bottle creation tool missing."
mkdir -p "$LOGS" "$HOME/Applications"

# Extract entitlements from the *original* Preview 27 app rather than making
# assumptions about the set used by CrossOver 26.3.
# Apple recommends extracting to stdout and converting the result with
# plutil. Directly requesting codesign to write a file may produce content
# that is not an XML plist on some macOS versions. Never invent entitlements.
extract_entitlements() {
    local src="$1" dst="$2" log="$3"
    local raw="$dst.raw" tmp="$dst.tmp"
    [ ! -e "$raw" ] && [ ! -e "$tmp" ] ||
        fail "Entitlement scratch files already exist; refusing to overwrite."
    # Read stdout separately: an otherwise valid signed Mac bundle may have
    # no embedded entitlements, which produces zero bytes. That's different
    # from malformed entitlements or a codesign failure.
    if ! codesign --display --entitlements - --xml "$src" >"$raw" 2>"$log"; then
        fail "codesign could not display the signature of $src. See $log."
    fi
    if [ -s "$raw" ]; then
        if ! plutil -convert xml1 -o "$tmp" "$raw" 2>>"$log"; then
            fail "Embedded entitlements are non-empty but unreadable. See $raw and $log."
        fi
    else
        # Only treat truly empty stdout as 'no embedded entitlements' when
        # the original signature itself verifies. Do not fabricate a copy of
        # unknown/invalid signing permissions.
        codesign --verify --strict "$src" >>"$log" 2>&1 ||
            fail "Signed bundle verification failed; refusing to infer empty entitlements."
        printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' \
            '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
            '<plist version="1.0"><dict></dict></plist>' > "$tmp"
        say "Verified signed app has no embedded entitlements; test-copy policy will add library validation exception only."
    fi
    [ -s "$tmp" ] && plutil -lint "$tmp" >/dev/null 2>&1 &&
        /usr/libexec/PlistBuddy -c 'Print' "$tmp" >/dev/null 2>&1 ||
        fail "Entitlements plist failed validation. See $log; no app copied."
    mv "$tmp" "$dst"
    rm -f "$raw"
}

ENT="$LOGS/original-entitlements.plist"
extract_entitlements "$ORIGINAL" "$ENT" "$LOGS/read-entitlements.log"
/usr/libexec/PlistBuddy -c 'Print' "$ENT" > "$LOGS/original-entitlements.txt" ||
    fail "Could not inspect the original entitlements."
[ -s "$LOGS/original-entitlements.txt" ] ||
    fail "Original entitlements are empty; refusing to re-sign the Preview copy."
/usr/libexec/PlistBuddy -c 'Add :com.apple.security.cs.disable-library-validation bool true' "$ENT" >/dev/null 2>&1 ||
    /usr/libexec/PlistBuddy -c 'Set :com.apple.security.cs.disable-library-validation true' "$ENT" >/dev/null ||
    fail "Could not set disable-library-validation in the isolated test app entitlements."

say "Copying original CrossOver Preview to $DEST (original untouched)."
if ! ditto "$ORIGINAL" "$DEST" > "$LOGS/ditto.log" 2>&1; then
    fail "Copy failed. A partial test app may remain at $DEST; original untouched. See $LOGS/ditto.log."
fi

TARGET_WINE="$DEST/Contents/SharedSupport/CrossOver/lib/wine"
for rel in x86_64-unix/ntdll.so x86_64-unix/crypt32.so x86_64-unix/winecoreaudio.so \
           x86_64-windows/version.dll x86_64-windows/crypt32.dll x86_64-windows/secur32.dll; do
    cp "$STAGE/$rel" "$TARGET_WINE/$rel" ||
        fail "Failed to replace $rel inside test app; original untouched."
    cmp -s "$STAGE/$rel" "$TARGET_WINE/$rel" ||
        fail "Copied test module mismatch: $rel"
done
say "All six staged modules installed into test app copy."

# CrossOver ships frameworks with CodeWeavers' own signature. Retain the
# existing entitlement set, with library validation disabled for mixed Team
# IDs, and ad-hoc sign only the copied outer app bundle.
if ! codesign --force --sign - -o runtime --entitlements "$ENT" "$DEST" \
        > "$LOGS/sign-app.log" 2>&1; then
    tail -25 "$LOGS/sign-app.log" >&2
    fail "Could not sign isolated app. Original CrossOver remains untouched."
fi
if ! codesign --verify --deep --strict "$DEST" > "$LOGS/verify-app.log" 2>&1; then
    tail -25 "$LOGS/verify-app.log" >&2
    fail "Test app signature verification failed. Do not open it yet."
fi

AFTER="$LOGS/test-app-entitlements.plist"
extract_entitlements "$DEST" "$AFTER" "$LOGS/verify-entitlements.log"
/usr/libexec/PlistBuddy -c 'Print :com.apple.security.cs.disable-library-validation' "$AFTER" |
    grep -Fqx true || fail "Library validation was not disabled in test app."
# Check every original entitlement key survived the signing step.
awk '/^[[:space:]]*[A-Za-z0-9._-]+ = / {print $1}' "$LOGS/original-entitlements.txt" | while IFS= read -r key; do
    [ -n "$key" ] || continue
    /usr/libexec/PlistBuddy -c "Print :$key" "$AFTER" >/dev/null 2>&1 ||
        fail "Original entitlement was lost on the copy: $key"
done
say "PASS: isolated app is signed and keeps original entitlements."

# This bottle has its own directory. The original Aurora17 bottle and any
# other user's CrossOver bottles are not changed or used.
COPY_CXB="$DEST/Contents/SharedSupport/CrossOver/bin/cxbottle"
say "Creating a new Windows 10 64-bit bottle: $BOTTLE"
if ! "$COPY_CXB" --bottle "$BOTTLE" --create --template win10_64 \
        --description "FIFA 17 CrossOver 27 isolated test" \
        > "$LOGS/create-bottle.log" 2>&1; then
    tail -25 "$LOGS/create-bottle.log" >&2
    fail "Could not create test bottle. The isolated test app copy remains; original app and bottles are untouched."
fi
CONF="$BOTTLES/$BOTTLE/cxbottle.conf"
[ -f "$CONF" ] || fail "Bottle tool did not create expected config: $CONF"
# The three FIFA17 environment settings from the old working 26.3 setup.
for key in CX_GRAPHICS_BACKEND CX_DR_TRAP WINE_SIMULATE_WRITECOPY; do
    if grep -Eq "^\"?$key\"?[[:space:]]*=" "$CONF"; then
        fail "New test bottle already defines $key; refusing to add duplicate settings."
    fi
done
CONF_TEMP="$BOTTLES/$BOTTLE/cxbottle.conf.cx27-tmp"
[ ! -e "$CONF_TEMP" ] || fail "Temporary test bottle config already exists."
awk '
    BEGIN { inserted=0 }
    /^\[EnvironmentVariables\]$/ && !inserted {
        print
        print "\"CX_GRAPHICS_BACKEND\" = \"d3dmetal\""
        print "\"CX_DR_TRAP\" = \"2\""
        print "\"WINE_SIMULATE_WRITECOPY\" = \"1\""
        inserted=1
        next
    }
    {print}
    END {
        if (!inserted) {
            print ""
            print "[EnvironmentVariables]"
            print "\"CX_GRAPHICS_BACKEND\" = \"d3dmetal\""
            print "\"CX_DR_TRAP\" = \"2\""
            print "\"WINE_SIMULATE_WRITECOPY\" = \"1\""
        }
    }' "$CONF" > "$CONF_TEMP" ||
    fail "Could not prepare test bottle environment."
mv "$CONF_TEMP" "$CONF" ||
    fail "Could not save test bottle environment."
say "PASS: test bottle graphics, trap and copy-on-write settings configured."

# Ensure the local native version.dll shim can take precedence when
# Aurora17 puts it next to FIFA17.exe. This command changes only the NEW
# disposable bottle, not any existing Aurora17 installation.
COPY_WINE="$DEST/Contents/SharedSupport/CrossOver/bin/wine"
if ! "$COPY_WINE" --bottle "$BOTTLE" reg add 'HKCU\Software\Wine\DllOverrides' \
         /v version /t REG_SZ /d native,builtin /f > "$LOGS/version-override.log" 2>&1; then
    tail -20 "$LOGS/version-override.log" >&2
    fail "Could not configure the version.dll override in test bottle."
fi
say "PASS: version.dll native,builtin override configured in test bottle."

say ""
say "ISOLATED TEST APP READY: $DEST"
say "TEST BOTTLE: $BOTTLE"
say "The original /Applications/CrossOver Preview.app and existing bottles were not modified."
say "Next: open the copied CrossOver app and use ONLY the $BOTTLE bottle to launch or install Aurora17/FIFA17."
say "This is the first real runtime test; gameplay success is not yet confirmed."
