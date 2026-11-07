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

## Step 2: obtain the matching Wine source (no CodeWeavers login needed)

A public **Wine-only** source tree from the matching CrossOver Preview build
is included in [MacGameFix 1.6.0](https://github.com/MathiasKowoll/MacGameFix/releases/tag/v1.6.0),
distributed as source for that project's LGPL Wine modules:

**[Download wine-source-crossover-preview-20261015.tar.xz](https://github.com/MathiasKowoll/MacGameFix/releases/download/v1.6.0/wine-source-crossover-preview-20261015.tar.xz)**

SHA-256 published by GitHub for this release asset:

```
964f820cf6438f1b256fa66b78a6a4f0144a76c854fbf4bdc9ad422bbf094dc7
```

The audit checks this checksum before unpacking. The file is **Wine source
only**, not the full CodeWeavers source package; that is sufficient for
**source patch compatibility auditing**, but not proof that the other parts
of a full CrossOver runtime build can be reproduced. It is redistributed
by a third party, not an official CodeWeavers download.

Alternatively, eligible CodeWeavers Preview members can download
`crossover-sources-20261015.tar.gz` directly from the
[Preview download centre](https://www.codeweavers.com/preview/download).
Do not use the stable 26.3 archive, and do not use the 20261006 preview
archive even though it has the same Wine major/minor release.

## Step 3: run a non-destructive patch audit

From Terminal, clone this development branch and run the audit on the
public archive downloaded to `~/Downloads`:

```sh
git clone --branch crossover-27-port https://github.com/kiankarbassian/FIFA-17-auroa-local-crossover27-patch-.git
cd FIFA-17-auroa-local-crossover27-patch-
/bin/zsh tools/audit-crossover27.zsh "$HOME/Downloads/wine-source-crossover-preview-20261015.tar.xz"
```

The audit verifies the third-party archive's published SHA-256, extracts
a **disposable** Wine source tree and applies the original patch series in
build order. It writes `crossover27-port-report/summary.txt` plus one log
per patch. It **does not touch CrossOver.app, Wine bottles, or game files**.
It stops at the first conflicting patch, as later patches can depend on
earlier ones. The audit accepts the full official 20261015 tar.gz archive
as well.

Provide `summary.txt` and the first conflicting patch's log for porting.
Do not share game executables, licence files or credentials.

## First Rosetta source patch rebased (uncompiled)

The first audit reported six failed hunks in
`dlls/ntdll/unix/signal_x86_64.c`. The initial rebase is committed as
[`patches/crossover-27-fifa17-rosetta.patch`](patches/crossover-27-fifa17-rosetta.patch).

The six revised hunks were checked against the uploaded
`signal_x86_64.c` source from Preview 20261015: all six have an exact matching
old-side context, and applying their line changes to that source succeeded in
the patch-generation check. The wrapper context now uses
`get_thread_data()` and `get_syscall_frame(data)`; the SIGSEGV path now uses
`sigcontext` and passes `data` explicitly to `leave_handler` and exception
handlers. **This is source matching only, not a compilation or gameplay test.**

The audit script now uses this CrossOver 27-specific first patch, followed by
the original CrossOver 26.3 patches. The original 26.3 patch stays untouched.
Rerun the audit to determine whether this full patch, including its other
source files, and the subsequent patches apply. **Do not run build.sh against
CrossOver 27 yet**: it still uses the 26.3-specific build configuration and
payload until the complete port has been verified.

## Online patch source rebase

The following audit then reported conflicts in the original 26.3 online patch:
`dlls/secur32/schannel.c` (2 hunks) and `dlls/crypt32/pfx.c`
(1 hunk). Its `dlls/ntdll/unix/virtual.c` hunks applied in the user audit.

The CrossOver Preview 20261015 `pfx.c` **already** calls
`CRYPT32_AllocateUniqueContainerName()` and uses an RSA/AES provider, so
the earlier unique-container patch was **removed**, not forced onto the new
source. The new `schannel.c` fallback preserves Wine 11.17's
`convert_capi_to_bcrypt()` conversion and existing NCrypt fallback,
rather than injecting the old Wine 26.3 code that returned CAPI blobs
directly to GnuTLS.

The 27-specific patch is
[`patches/crossover-27-fifa17-online.patch`](patches/crossover-27-fifa17-online.patch).
The inserted `schannel.c` hunks were validated locally against the uploaded
Preview 20261015 `schannel.c` with `patch -p1 --fuzz=0`: both a dry-run
and application succeeded exactly. The remaining `virtual.c` hunks are
taken unchanged from the original online patch, which the earlier
on-device audit reported as passing.

**This is a source-only verification.** The full revised online patch must
still be rerun against the complete Wine source tree, then compiled and
tested. The next unported patch is the original 26.3 `fifa17-audio.patch`.
The original 26.3 online patch stays untouched.

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
