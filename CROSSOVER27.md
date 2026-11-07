# CrossOver 27 port: work in progress

> **NOT READY TO INSTALL OR PLAY.** This branch is a porting workspace, not a
> working FIFA 17 patch. Do not run the inherited `START HERE*.command`,
> `setup.sh`, or `Fix my installation.command` against CrossOver 27.
> They install binaries built for CrossOver **26.3**, and the 26.3 guard is
> deliberate.

## Why a version-number change is unsafe

The original `fixes/` Mach-O and PE files are built against CodeWeavers'
CrossOver 26.3 Wine sources. CrossOver 27 changes Wine implementation details,
and may offer both an Intel/Rosetta Wine path and a native ARM64/FEX path.
The first goal is the **Intel/Rosetta Wine path only**, to minimise differences.
The ARM64/FEX path is a separate port and is **not supported** here.

The original installer also edits copies of CrossOver's own `ws2_32.so` and
`wineserver`, adjusts load commands, signs binaries and configures bottles.
A passing patch dry-run cannot validate those steps, nor prove FIFA 17 launches.

## Target build (verified source mapping)

| Item | Required |
|---|---|
| CrossOver | **Preview 27.0.0.41073** |
| Release ID | **20261015** |
| Wine source | **Wine 11.17**, CodeWeavers' patched tree |
| Source archive | **`crossover-sources-20261015.tar.gz`** |
| Initial engine | **x86_64 / Intel side under Rosetta** |

Build-to-source mapping: [MacGameFix engine documentation](https://github.com/MathiasKowoll/MacGameFix/blob/main/engine/README.md#modules).
The matching archive is distributed through the
[CodeWeavers Preview download centre](https://www.codeweavers.com/preview),
which requires a qualifying CodeWeavers account. The normal
[CrossOver source page](https://www.codeweavers.com/crossover/source) currently
lists the stable 26.3.0 source, **not the source needed for this port**.

The archive ID matters. **Do not use**
`crossover-sources-20261006.tar.gz` (27.0.0.41069), even though it also
reports Wine 11.17. Changes in `ntdll/loader.c` were reported between these
two previews, and the FIFA 17 patches modify `ntdll`.

## Step 1: confirm the running engine

On your Mac, **CrossOver > About CrossOver** should show
`Version 20261015 (27.0.0.41073)`. Use the **Intel/Rosetta** engine for
this initial port. This does not assert that the native ARM64/FEX engine will
work with these binaries.

## Step 2: obtain the exact Wine source

Download `crossover-sources-20261015.tar.gz` from the CodeWeavers Preview
centre while signed in to the account that has Preview access. Keep the
archive **outside** the GitHub repository; don't commit the large source
archive or any proprietary CrossOver executable.

## Step 3: run a non-destructive patch audit

In Terminal, from a clone of this branch:

```sh
/bin/zsh tools/audit-crossover27.zsh /path/to/matching-crossover-sources.tar.gz
```

Alternatively give the script a directory that contains `sources/wine`,
`wine/`, or the Wine source itself. It extracts or copies sources into a
temporary directory, applies the original patch series in build order, and
writes the results to `crossover27-port-report/`. It **does not touch any
installed CrossOver app, Wine bottle, or your game files**. It stops at the
first conflicting patch, because later patches can depend on earlier ones.

Share `crossover27-port-report/summary.txt` and the log of the first
conflicting patch. Do not publish unrelated local paths, credentials,
game executables or licence files.

## What must happen before any CrossOver 27 installer is enabled

1. Port failed patches to the corresponding CrossOver 27 Wine source.
2. Build all patched Mach-O/PE components for the selected **x86_64** runtime,
   using the new source tree and a compatible compiler/SDK.
3. Review the CrossOver 27 runtime layout and verify library symbols, ABIs,
   rpaths, load-command modifications and signatures, including the original
   ws2_32/wineserver modifications.
4. Replace the 26.3-only payload with binaries built from the 27 sources,
   record new checksums, and update version guards **only after** those checks.
5. Test in a disposable **copy** of CrossOver 27, never the original app.
   Test offline launch, menus, audio, graphics, controller and gameplay.
6. Keep installers disabled for CrossOver 27 until these steps pass.

No untested CrossOver 27 support is claimed. The original upstream 26.3
release is unaffected.
