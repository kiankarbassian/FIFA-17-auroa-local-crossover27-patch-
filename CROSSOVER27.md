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

## CoreAudio patch rebase (source checked, not compiled)

After Rosetta and online patches passed, the next audit conflict was in
`crossover-26.3-fifa17-audio.patch`. Its old CoreAudio changes have been
rebased against the uploaded `coreaudio.c` and `authorization.m` source
from CrossOver Preview 20261015.

The new patch is
[`patches/crossover-27-fifa17-audio.patch`](patches/crossover-27-fifa17-audio.patch).
Its seven `coreaudio.c` hunks were generated from exact source positions and
verified for exact old-side context and unified-diff hunk counts against
the uploaded Preview source. The `authorization.m` changes retain the
original 26.3 permission-wait implementation, as the uploaded source still
uses the old unbounded wait.

Port-specific safeguards:
- Use `AUTHORIZED` explicitly for AVFoundation status comparisons:
  `CoreAudio_get_capture_authorization_status()` returns an enum
  (where DENIED is not zero), but the permission request callback returns
  a boolean.
- Reject `NULL` audio units in `unix_is_format_supported` rather
  than passing them to the setup routine.
- Preserve device exclusion and bounded microphone permission prompting.

The original 26.3 CoreAudio patch is unchanged. **Neither the complete
audio patch nor the final Wine binaries have been built or tested yet.**
Rerun the full audit to see which later patch requires adaptation.

## Bulk triage (reduce repeated patch-by-patch exchanges)

The first three patches now pass the user's audit: Rosetta, online and CoreAudio.
The fourth patch, the original CrossOver 26.3 CNG patch, conflicts. The old CNG patch
is a large Wine 26.3-specific cryptography implementation; several pieces
are already present or changed in Wine 11.17. In particular, Preview 20261015
`pfx.c` has a unique PFX key container and an implementation of
`PFXExportCertStoreEx`, although `PKCS12_ALWAYS_CNG_KSP` is still logged
as ignored. It should be adapted as a targeted fix, not blindly applied.

To expose more potential issues in one run, use:

```sh
cd ~/FIFA-17-auroa-local-crossover27-patch-
git pull --ff-only
AUDIT_ALL=1 /bin/zsh tools/audit-crossover27.zsh \
  "$HOME/Downloads/wine-source-crossover-preview-20261015.tar.xz"
cat crossover27-port-report/summary.txt
```

With `AUDIT_ALL=1`, a conflicting patch is **skipped** in the disposable
source tree, and subsequent patches are checked against that tree. Results
after the first skipped patch, even PASS results, are **provisional**:
later patches may depend on skipped ones. The normal audit without
`AUDIT_ALL=1` still stops at its first conflict.

## Bulk audit interpretation: minimal FIFA 17 / Aurora17 scope

The user ran the opt-in bulk audit against Wine source for CrossOver Preview
20261015. Results: 3 confirmed source-application passes, 4 provisional
passes, and 9 conflicts. All findings after the CNG conflict are **provisional**
because the source tree omitted the conflicting CNG patch.

For **FIFA 17 with the Aurora17 launcher only**, focus on the four patches
listed unconditionally at the beginning of `build.sh`:

| Patch | Audit | Necessity |
| --- | --- | --- |
| `crossover-27-fifa17-rosetta.patch` | Pass | Core |
| `crossover-27-fifa17-online.patch` | Pass | Core |
| `crossover-27-fifa17-audio.patch` | Pass | Core |
| `crossover-26.3-fifa17-cng.patch` | Conflict | Core; requires a selective Wine 11.17 reimplementation |

The remaining eight conflicting patches must **not** be assumed to block a
minimal FIFA 17 installation:

| Original patch | Scope from its own documentation | Decision for minimal FIFA 17 |
| --- | --- | --- |
| `win32u-shm-flush-under-user-lock` | RebornFUT/WebView2 launcher workaround | Add only if using a launcher that needs it |
| `debug-register-emulation` | FIFA 16's CX_DR_TRAP=3 | Omit |
| `fifa16-dst-complement` | FIFA 16 protector-specific workaround | Omit |
| `drtrap-syscall-stub` | FIFA 16 mode-3 performance workaround | Omit |
| `game-profiles` | Per-executable settings when launching multiple FIFA titles from one bottle | Omit for FIFA 17-only bottle |
| `fifa17-folder-gate` | Reconcile one FIFA 17 game folder shared among Aurora/CAS/Impulsum launchers | Add only if switching between those launchers |
| `remote-thread-exit` | FIFA 20 with REFUT | Omit |
| `aurora-elevate` | Aurora launcher admin token for FIFA 21 | Omit |

The provisional passing fixes (`topdown-alloc-limit`, `gdiplus-delete-font-collection`,
`ole32-revoke-foreign-window`, `pf-pae-enabled`) are also not essential
to the basic FIFA 17-only path based on their documented purposes.

The CNG patch is not a one-to-one port. Wine 11.17 already has several of
the original 26.3 patch's features, including the unique PFX import key
container and a non-stub `PFXExportCertStoreEx`. The uploaded Preview
`pfx.c` still ignores `PKCS12_ALWAYS_CNG_KSP`, so functionality remains
to be implemented and validated. The exact set of remaining gaps must be
determined from the current Wine code and .NET integration tests.

Even if the first four patches apply, **`build.sh`, `setup.sh`, and all
prebuilt `fixes/` are still CrossOver 26.3-specific**. A successful source
audit alone does not create a CrossOver 27 build or prove that FIFA 17 boots,
runs, or connects. The public Wine-only source release may not contain every
dependency needed to reproduce CodeWeavers' CrossOver engine.

## Minimal FIFA 17 CNG port prepared (not yet compiled)

A focused [`crossover-27-fifa17-cng-minimal.patch`](patches/crossover-27-fifa17-cng-minimal.patch)
has been committed. **This is a source candidate, not a confirmed working
fix.** Unlike the 39 KB CNG patch written for CrossOver 26.3, it changes
only `dlls/crypt32/pfx.c`:

- Implements handling of `PKCS12_ALWAYS_CNG_KSP`, which Wine 11.17
  accepts but explicitly ignores.
- Imports the existing CAPI RSA key blob into NCrypt as
  `BCRYPT_RSAFULLPRIVATE_BLOB`, using the original 26.3 patch's
  bounds-checked conversion.
- Attaches the NCrypt key to one matching certificate with
  `CERT_NCRYPT_KEY_HANDLE_PROP_ID` rather than distributing one
  handle across a whole certificate chain.
- Rejects failed CNG import instead of silently returning a legacy key.
- Preserves Wine 11.17's existing key-container naming, CNG certificate
  property support, export implementation, and Unix-side GnuTLS structures.

The supplied Preview 20261015 `pfx.c` differs from the upstream
Wine 11.17 `pfx.c` only by a trailing newline in the file
retrieval, so both revised pfx hunks have been verified for exact
original-side context and line counts. The other Wine 11.17 source
files used for comparison were fetched from upstream Wine, **not yet
verified against the user's exact CrossOver Preview source**.

### Strict FIFA 17-only audit

```sh
cd ~/FIFA-17-auroa-local-crossover27-patch-
git pull --ff-only
FIFA17_ONLY=1 /bin/zsh tools/audit-crossover27.zsh \
  "$HOME/Downloads/wine-source-crossover-preview-20261015.tar.xz"
```

This checks all **four** patches in order on a disposable source tree,
plus seven required CNG source symbols in the exact Preview tree.
Do not set `AUDIT_ALL=1` in minimal mode. Success is a source patch
check **only**; no compilation or game execution has happened yet.

### Build feasibility

MacGameFix's [Wine 11.17 engine build instructions](https://github.com/MathiasKowoll/MacGameFix/blob/main/engine/README.md)
document building CrossOver Preview 20261015 Wine modules using the
`sources/wine` subtree from CodeWeavers' release, Xcode tools,
llvm-mingw and Homebrew bison. Its public `wine-source-crossover-preview-20261015.tar.xz`
is described as the exact Wine source tree it used to build modules.
This is evidence that **module compilation may be feasible** from
the available Wine-only source, rather than needing the full CrossOver
source bundle just to compile a few modules. We have not yet
reproduced its build with this patch set.

The existing FIFA repo's `build.sh`, `setup.sh`, checksums and
precompiled `fixes/` still target CrossOver 26.3. Do **not** use
those scripts to install into CrossOver Preview 27. The eventual
build must use the correct macOS x86_64 Wine 11.17 toolchain,
verify PE/Unix architectures, exports/imports and GnuTLS support,
and install into an isolated copy only.

## Four-patch source audit PASSED on Mac (2026-11-07)

The user ran `FIFA17_ONLY=1 tools/audit-crossover27.zsh` against the verified
Preview 20261015 Wine 11.17 source archive. Result:

```
PASS  crossover-27-fifa17-rosetta.patch
PASS  crossover-27-fifa17-online.patch
PASS  crossover-27-fifa17-audio.patch
PASS  crossover-27-fifa17-cng-minimal.patch
Audit finished: 4 passed, 0 conflicting, 0 absent.
```

This confirms source patch application, not C/C++ compilation, Wine ABI
compatibility or game operation.

### First build and toolchain test (does NOT install anything)

A new isolated build script is available at
[`tools/build-crossover27-minimal.sh`](tools/build-crossover27-minimal.sh).
Use it **instead of** the old CrossOver 26.3 `build.sh`.
First check the Mac toolchain:

```sh
cd ~/FIFA-17-auroa-local-crossover27-patch-
git pull --ff-only
sh tools/build-crossover27-minimal.sh --check
```

It checks the x86_64 Apple clang linker/SDK, a Windows x86_64 mingw-w64
compiler, Bison 3+, GnuTLS headers and basic utilities.
If an llvm-mingw binary is not on PATH, export
`LLVM_MINGW=/path/to/llvm-mingw` (containing `bin/`).
A failed check does not touch Wine or CrossOver.

After toolchain checks succeed, build with:

```sh
sh tools/build-crossover27-minimal.sh \
  "$HOME/Downloads/wine-source-crossover-preview-20261015.tar.xz"
```

This rechecks source SHA-256, copies the source into `crossover27-build/`,
strictly applies the **four** target patches, configures x86_64 Wine 11.17,
enables the same GnuTLS Unix crypto code used by the original 26.3 port
and attempts five Wine module make targets. It collects the following
built modules in a **separate** directory:

- `x86_64-unix/ntdll.so`, `crypt32.so`, `winecoreaudio.so`
- `x86_64-windows/version.dll`, `crypt32.dll`, `secur32.dll`

The initial build script stopped after extraction because it assumed the
Wine sources lived directly in `source/wine` or `source/sources/wine`.
The revised script searches nested archive directories for `dlls/`
and `VERSION`, then checks for `configure` separately. It can resume
this exact **source-only** interrupted run from `crossover27-build/`
when the build, logs and payload directories are empty. No deletion or
re-extraction is required. If any build output already exists, it
refuses to overwrite it.

Full build logs are under `crossover27-build/logs/`.
The script has **not yet been run on macOS**, so configure or compile
issues may need correction. Output is not installed, signed or used in a
bottle. A successful build will still require comparing library
dependencies, exports/imports, rpaths and runtime behaviour against the
CrossOver 27 binaries before considering an isolated install. In
particular, confirm CrossOver 27 ships the GnuTLS dylib with the name
used by the built `crypt32.so`.

## Minimal CrossOver 27 build succeeded on the user's Mac (2026-11-07)

After correcting the archive's nested Wine source-directory detection, the
user's local `tools/build-crossover27-minimal.sh` run reported:

```
Source: Wine 11.17 CrossOver Preview 20261015
SUCCESS: all six module files built and checked for their expected architectures.
NOT INSTALLED: do not copy these files into CrossOver before ABI and runtime review.
```

This confirms the patch series can compile the six *targeted* modules on
the user's Apple-silicon Mac, not that the compiled binaries are safe to
install into Preview 27, or that FIFA 17 will launch.

A separate, **read-only** comparison helper is committed at
[`tools/audit-crossover27-binaries.zsh`](tools/audit-crossover27-binaries.zsh):

```sh
cd ~/FIFA-17-auroa-local-crossover27-patch-
git pull --ff-only
/bin/zsh tools/audit-crossover27-binaries.zsh
```

If the app is installed under an unusual name/location, pass the full
`.app` path as its only argument. The script requires exact installed
`CFBundleVersion` **27.0.0.41073**, verifies the built
`payload/SHA256SUMS`, and gathers read-only metadata for the original
and built Wine modules: architectures, Mach-O linked libraries, LC_RPATH
entries, exported symbols, code-signing information, and PE headers
(where mingw objdump is available). It writes only
`crossover27-build/abi-report/` and `abi-report.zip`; the ZIP contains
text reports and no binaries.

This is an **ABI triage**, not full compatibility verification. In
particular, inspect missing stock exports, loader paths, minimum macOS,
code signatures and PE imports/exports manually before any isolated
installation. No automatic CrossOver modification is authorised by
this script.

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
