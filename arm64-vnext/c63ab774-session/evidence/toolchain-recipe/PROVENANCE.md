# Toolchain recipe - consolidated provenance

Consolidated 2026-09-03 because the evidence directory preserved the SOURCE state
completely but NOT the TOOLCHAIN, which is a precondition it does not contain.
`/root/xc/inst` was listed under "preserved assets" but existed only as live WSL
filesystem state - in no diff, no repo, no archive. LISTING IS NOT PRESERVING.

Files were COPIED read-only; originals were not modified or moved.
Every copy was verified byte-identical to its source at copy time.

## INPUT SOURCE IDENTITIES — clone THESE SHAs, not the branch

**BRANCH-PINNING WEAKNESS:** every clone in this recipe is `--depth 1 --branch woarm64`.
If either branch advances, a replay **silently builds DIFFERENT sources with no signal**.
A successor must clone the recorded commit SHAs, not the branch tips.

| Input | Commit | Confidence |
|---|---|---|
| `gcc-src` | `5688a17320e775944bbe795010ebe7e89fc7a628` (woarm64, shallow) | **VERIFIED** — equals `crutkas/gcc-woarm64` `origin/woarm64` |
| `runtime` | `d890a845e992638a6f09560efacc26d15b3ffe6a` | **VERIFIED** — matches the diff base; all 43/43 pre-image blobs resolve |
| `mingw-w64` (w32api) | `819a6ec2ea87c19814b287e21d65e0dc7f05abba` | **VERIFIED** — `git tag --points-at` returns `v12.0.0` EXACTLY, and `v12.0.0^{commit}` returns this SHA (bidirectional) |
| `binutils` | `44335833f8f734f978211b082b15aed14efcf958` | **PRESUMED, NOW CORROBORATED — inference, not record** |

**Binutils — how far the corroboration goes, and where it stops.** The built tree is lost, so
the commit cannot be read back from it. However the installed binaries survive and report:

```
GNU ld (GNU Binutils) 2.44.50.20250131
GNU assembler (GNU Binutils) 2.44.50.20250131
```

That `20250131` stamp comes from `BFD_VERSION_DATE` in `bfd/version.h`. At
`crutkas/binutils-woarm64` `origin/woarm64` = `44335833f8f734f978211b082b15aed14efcf958`,
that file contains **`#define BFD_VERSION_DATE 20250131`** — an exact match. So the binary is
**consistent with** the presumed commit rather than contradicting it.

**This does NOT uniquely pin the SHA.** That date is bot-updated daily, so *any* commit from
that day carries the same stamp; the evidence narrows the candidate range to a one-day window
containing the presumed tip. It is corroboration, not identification. Had the date NOT fitted,
it would have **disproved** the presumption outright — which would have been more valuable.

**Portability, not data loss.** The scripts clone from `file:///mnt/c/Users/crutkasLocal/...`.
Both repos are pushed to GitHub with local tips matching origin, so those paths are a
**portability inconvenience, not a data-loss risk** — substitute the remote URL.
## Scope note

The authorised list named a subset (binutils.sh, ml.sh, s2/s14/s3/s4/s5/s6 and the
manifest). THE COMPLETE scratch chain was copied instead, deliberately: these are
sequential steps, and preserving s2-s6 + s14 while dropping s1, s7-s13 and s15-s22
would leave a successor holding a recipe with holes in it - the same discoverability
trap this consolidation exists to remove. Total cost is ~30 KB.

## Key scripts

- `from-1e64365a/clone-gcc.sh` - clones `gcc-woarm64` branch `woarm64` from the
  Windows-side local repo, using `git -c core.autocrlf=false` (correctly applying the
  export rule).
- `from-fca94a35/binutils.sh` - builds binutils for `aarch64-pc-cygwin`.
- **`from-1e64365a/gcc-cxx.sh` - BUILDS THE C++ CROSS COMPILER into `/root/xc/inst`**
  (`--enable-languages=c,c++`, `make -j12 all-gcc`, yielding cc1/cc1plus + drivers).
  This corrects an earlier assessment that no preserved script produced
  `aarch64-pc-cygwin-g++`. It does.
- `from-fca94a35/ml.sh` - a multilib PROBE into a separate `inst-ml` prefix; it is
  diagnostic, not part of the build chain.

## LIMITATION - STATE THIS PROMINENTLY

**THAT THESE SCRIPTS REPLAY CLEANLY IS UNTESTED.** Consolidation makes the recipe
FINDABLE, not VERIFIED. No toolchain rebuild has been performed to prove replay; that
is a multi-hour job and remains an OWNER DECISION. It is now a well-posed one.
External preconditions the scripts assume: a WSL guest with build dependencies, the
Windows-side `gcc-woarm64` and `msys2-runtime` clones, and network access for w32api.

## Provenance (verify a copy against its source while both still exist)

| Copy | Bytes | SHA-256 | Origin session | Original path |
|---|---:|---|---|---|
| `from-1e64365a/clone-gcc.sh` | 371 | `c5fb88896c265933e30854776194d1cc52d6bc8964232011eeccd49998cc1179` | `1e64365a-8e29-4b6b-80ea-34408c4d868b` | `C:\Users\crutkasLocal\.copilot\session-state\1e64365a-8e29-4b6b-80ea-34408c4d868b\files\scratch\clone-gcc.sh` |
| `from-1e64365a/clone-runtime.sh` | 1094 | `33584c5c38e386431e351645ba6de77283016fcd67342e5d3546a1cb669f90f8` | `1e64365a-8e29-4b6b-80ea-34408c4d868b` | `C:\Users\crutkasLocal\.copilot\session-state\1e64365a-8e29-4b6b-80ea-34408c4d868b\files\scratch\clone-runtime.sh` |
| `from-1e64365a/gcc-cxx.sh` | 1211 | `9a60456fe12d0c7c8262bb29870758b791b33748a83a2575d6aa17944e613116` | `1e64365a-8e29-4b6b-80ea-34408c4d868b` | `C:\Users\crutkasLocal\.copilot\session-state\1e64365a-8e29-4b6b-80ea-34408c4d868b\files\scratch\gcc-cxx.sh` |
| `from-1e64365a/p1.sh` | 945 | `2ddc8306498cbf167f2a808ca2fb555696d5c0f21413b0d41f9776364acafae8` | `1e64365a-8e29-4b6b-80ea-34408c4d868b` | `C:\Users\crutkasLocal\.copilot\session-state\1e64365a-8e29-4b6b-80ea-34408c4d868b\files\scratch\p1.sh` |
| `from-1e64365a/p2.sh` | 991 | `35aff2ecdc9a8a4be3f8cfddb19f62946528fe830c5c60b44336552df5866350` | `1e64365a-8e29-4b6b-80ea-34408c4d868b` | `C:\Users\crutkasLocal\.copilot\session-state\1e64365a-8e29-4b6b-80ea-34408c4d868b\files\scratch\p2.sh` |
| `from-1e64365a/p3.sh` | 791 | `19279aa28784e15429a06778b8cba972e62c346bc347cb3571e70c55caa12977` | `1e64365a-8e29-4b6b-80ea-34408c4d868b` | `C:\Users\crutkasLocal\.copilot\session-state\1e64365a-8e29-4b6b-80ea-34408c4d868b\files\scratch\p3.sh` |
| `from-1e64365a/s1.sh` | 644 | `f750858dad5e890647d3e06b3cbf716c9a0df5e4d7bda9a515bc368ffdde5e64` | `1e64365a-8e29-4b6b-80ea-34408c4d868b` | `C:\Users\crutkasLocal\.copilot\session-state\1e64365a-8e29-4b6b-80ea-34408c4d868b\files\scratch\s1.sh` |
| `from-1e64365a/s10.sh` | 395 | `1d16aacdcba88803c99cbe71c007b0a7f6a9905b73d564a16113fe1db37a6dd5` | `1e64365a-8e29-4b6b-80ea-34408c4d868b` | `C:\Users\crutkasLocal\.copilot\session-state\1e64365a-8e29-4b6b-80ea-34408c4d868b\files\scratch\s10.sh` |
| `from-1e64365a/s11-patch.sh` | 1278 | `055b03ad3a921bedf6e7f10fa11c63a197456006767168631bb16b93df84cc41` | `1e64365a-8e29-4b6b-80ea-34408c4d868b` | `C:\Users\crutkasLocal\.copilot\session-state\1e64365a-8e29-4b6b-80ea-34408c4d868b\files\scratch\s11-patch.sh` |
| `from-1e64365a/s12-make3.sh` | 1149 | `ab551952698678f30163ad65c837e5b1c240b34e41f1f422d52a25af36c18a70` | `1e64365a-8e29-4b6b-80ea-34408c4d868b` | `C:\Users\crutkasLocal\.copilot\session-state\1e64365a-8e29-4b6b-80ea-34408c4d868b\files\scratch\s12-make3.sh` |
| `from-1e64365a/s13-mbstate.sh` | 726 | `4a31d100b8813faa57eec7c7d3fbf696c382c57b4cf881e329efe8614c6ef267` | `1e64365a-8e29-4b6b-80ea-34408c4d868b` | `C:\Users\crutkasLocal\.copilot\session-state\1e64365a-8e29-4b6b-80ea-34408c4d868b\files\scratch\s13-mbstate.sh` |
| `from-1e64365a/s14-w32api-v12.sh` | 1667 | `7f37c0147d3bf5d4fe23670a3f7f210a54b872256855b1f68192e30c87a2b3db` | `1e64365a-8e29-4b6b-80ea-34408c4d868b` | `C:\Users\crutkasLocal\.copilot\session-state\1e64365a-8e29-4b6b-80ea-34408c4d868b\files\scratch\s14-w32api-v12.sh` |
| `from-1e64365a/s15-make4.sh` | 1744 | `85832d8400a0f60edcf40caa04026046d3ecc0290bb43a9d44b93ad1c031beb2` | `1e64365a-8e29-4b6b-80ea-34408c4d868b` | `C:\Users\crutkasLocal\.copilot\session-state\1e64365a-8e29-4b6b-80ea-34408c4d868b\files\scratch\s15-make4.sh` |
| `from-1e64365a/s16-report.sh` | 1305 | `6ec5810c864ff1e1030df7a44c81168a77479d0f66ce82eb5ed0eedd5a75ad98` | `1e64365a-8e29-4b6b-80ea-34408c4d868b` | `C:\Users\crutkasLocal\.copilot\session-state\1e64365a-8e29-4b6b-80ea-34408c4d868b\files\scratch\s16-report.sh` |
| `from-1e64365a/s17-detail.sh` | 713 | `128986509560b62cf05cf4e20516111b7263ea5314fcc110c2f21de77581a966` | `1e64365a-8e29-4b6b-80ea-34408c4d868b` | `C:\Users\crutkasLocal\.copilot\session-state\1e64365a-8e29-4b6b-80ea-34408c4d868b\files\scratch\s17-detail.sh` |
| `from-1e64365a/s18-malign.sh` | 581 | `ed8b63d3e066fa7b09e04e6b67f1d9bd64dc878193cba349e0a6ad91726cde04` | `1e64365a-8e29-4b6b-80ea-34408c4d868b` | `C:\Users\crutkasLocal\.copilot\session-state\1e64365a-8e29-4b6b-80ea-34408c4d868b\files\scratch\s18-malign.sh` |
| `from-1e64365a/s19-verify.sh` | 2575 | `b49c66a1b9f059e8c97e5f03b2989a34bd0d6c0e34f31cbe39c67582535d3efd` | `1e64365a-8e29-4b6b-80ea-34408c4d868b` | `C:\Users\crutkasLocal\.copilot\session-state\1e64365a-8e29-4b6b-80ea-34408c4d868b\files\scratch\s19-verify.sh` |
| `from-1e64365a/s2-w32api.sh` | 804 | `c17fcce692e1ca24f07dea37ebec734187aac8f22591326d656028403004e5a8` | `1e64365a-8e29-4b6b-80ea-34408c4d868b` | `C:\Users\crutkasLocal\.copilot\session-state\1e64365a-8e29-4b6b-80ea-34408c4d868b\files\scratch\s2-w32api.sh` |
| `from-1e64365a/s20-final.sh` | 873 | `9568311191c202c00abc78618cf32e048c2977bb49734084cb55afc203a0ddb3` | `1e64365a-8e29-4b6b-80ea-34408c4d868b` | `C:\Users\crutkasLocal\.copilot\session-state\1e64365a-8e29-4b6b-80ea-34408c4d868b\files\scratch\s20-final.sh` |
| `from-1e64365a/s21-last.sh` | 593 | `6fdc269fba2e119a85dd8250762cb74f6aeabd50074400fa1f559f8b2f8733e7` | `1e64365a-8e29-4b6b-80ea-34408c4d868b` | `C:\Users\crutkasLocal\.copilot\session-state\1e64365a-8e29-4b6b-80ea-34408c4d868b\files\scratch\s21-last.sh` |
| `from-1e64365a/s22-evidence.sh` | 2115 | `70522639b2dd1e95108691251d378656701f41e22faec8d30397405caef88a89` | `1e64365a-8e29-4b6b-80ea-34408c4d868b` | `C:\Users\crutkasLocal\.copilot\session-state\1e64365a-8e29-4b6b-80ea-34408c4d868b\files\scratch\s22-evidence.sh` |
| `from-1e64365a/s3-newlib.sh` | 634 | `ce99bdfa2730ac9c0199749b57bb308a6415eda5318468a68d1287917848ad04` | `1e64365a-8e29-4b6b-80ea-34408c4d868b` | `C:\Users\crutkasLocal\.copilot\session-state\1e64365a-8e29-4b6b-80ea-34408c4d868b\files\scratch\s3-newlib.sh` |
| `from-1e64365a/s4-autoreconf.sh` | 836 | `54cdf3d23875c0cca04dccac962969d4eec21923df21ab4baa9d1ce4d575e906` | `1e64365a-8e29-4b6b-80ea-34408c4d868b` | `C:\Users\crutkasLocal\.copilot\session-state\1e64365a-8e29-4b6b-80ea-34408c4d868b\files\scratch\s4-autoreconf.sh` |
| `from-1e64365a/s5-winsupcfg.sh` | 840 | `4a258d93e345e6b5958f182b33c395856c8862fce3bcfd3e9e3d0cf497053982` | `1e64365a-8e29-4b6b-80ea-34408c4d868b` | `C:\Users\crutkasLocal\.copilot\session-state\1e64365a-8e29-4b6b-80ea-34408c4d868b\files\scratch\s5-winsupcfg.sh` |
| `from-1e64365a/s6-winsupcfg2.sh` | 1092 | `d68a19f91881df311d0fa1a20cb776c444468c46c86ccc9ad3731fda5b694f7e` | `1e64365a-8e29-4b6b-80ea-34408c4d868b` | `C:\Users\crutkasLocal\.copilot\session-state\1e64365a-8e29-4b6b-80ea-34408c4d868b\files\scratch\s6-winsupcfg2.sh` |
| `from-1e64365a/s7-make.sh` | 764 | `2cca98c2ad2f1bea7004a250df4e1384fd57a4e35bb0f14cacafa6e3e40fe8a2` | `1e64365a-8e29-4b6b-80ea-34408c4d868b` | `C:\Users\crutkasLocal\.copilot\session-state\1e64365a-8e29-4b6b-80ea-34408c4d868b\files\scratch\s7-make.sh` |
| `from-1e64365a/s8-make2.sh` | 944 | `baa674f738ec5ff9cceccf4ce9d94dd65037ea234265bf6aea81c2457bb6eb51` | `1e64365a-8e29-4b6b-80ea-34408c4d868b` | `C:\Users\crutkasLocal\.copilot\session-state\1e64365a-8e29-4b6b-80ea-34408c4d868b\files\scratch\s8-make2.sh` |
| `from-1e64365a/s9-uintptr.sh` | 1065 | `1321d5f7fc6cf984863c0b61b640f4a8ea499b1f88d0ca6e4801c5949b486152` | `1e64365a-8e29-4b6b-80ea-34408c4d868b` | `C:\Users\crutkasLocal\.copilot\session-state\1e64365a-8e29-4b6b-80ea-34408c4d868b\files\scratch\s9-uintptr.sh` |
| `from-1e64365a/toolchain-manifest.txt` | 1339 | `655c97ccd5a690604fec9fb95b6826703688d1ceea9f4425e04ac01f67ca61fa` | `1e64365a-8e29-4b6b-80ea-34408c4d868b` | `C:\Users\crutkasLocal\.copilot\session-state\1e64365a-8e29-4b6b-80ea-34408c4d868b\files\evidence\toolchain-manifest.txt` |
| `from-fca94a35/binutils.sh` | 840 | `4b14b971e641549d29e8c6598e37df4308d63ee3836b6a1539d14c8a6bf395b7` | `fca94a35-047d-478d-8d6c-e8af786c4875` | `C:\Users\crutkasLocal\.copilot\session-state\fca94a35-047d-478d-8d6c-e8af786c4875\files\scratch\binutils.sh` |
| `from-fca94a35/ml.sh` | 738 | `09b573779b3ab931f229867adb3e3af7de59da87a39903bba22fb495bbff7839` | `fca94a35-047d-478d-8d6c-e8af786c4875` | `C:\Users\crutkasLocal\.copilot\session-state\fca94a35-047d-478d-8d6c-e8af786c4875\files\scratch\ml.sh` |
