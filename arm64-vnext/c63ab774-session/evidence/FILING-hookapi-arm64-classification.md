# Cygwin/MSYS2: AArch64 executables are misclassified as non-Cygwin, breaking exec

**Status:** root cause identified, one-line fix, verified on hardware.
**Affects:** any AArch64 (ARM64) build of the Cygwin/MSYS2 runtime.
**Not affected:** x86_64, which is the only architecture in the allowlist.

## Summary

`PEHeaderFromHModule()` in `winsup/cygwin/hookapi.cc` rejects every PE whose
machine type is not `IMAGE_FILE_MACHINE_AMD64`. On AArch64 this makes Cygwin
unable to recognise its own executables, which in turn causes `exec` of one
Cygwin program from another to fail with `ERROR_INVALID_HANDLE`.

The failure surfaces three subsystems away from its cause, as:

    child_copy: cygheap read copy failed, 0x800000000..0x800025B30,
                done 0, windows pid NNNNN, Win32 error 6
    *** fatal error - couldn't create signal pipe, Win32 error 5

## The defect

`winsup/cygwin/hookapi.cc`, `PEHeaderFromHModule()`:

    /* Return valid PIMAGE_NT_HEADERS only for supported architectures. */
    switch (pNTHeader->FileHeader.Machine)
      {
      case IMAGE_FILE_MACHINE_AMD64:
        break;
      default:
        return NULL;
      }

`IMAGE_FILE_MACHINE_ARM64` (0xAA64) takes `default:` and the function returns
NULL. `hook_or_detect_cygwin()` then short-circuits on `if (!pExeNTHdr)`.

## Why it breaks exec

Classification is done by inspecting the image, not by mount flags:

    spawn.cc:1225   real_path.set_cygexec (hook_or_detect_cygwin (buf, NULL,
                                                                  subsys, hm));

so a NULL return clears `MOUNT_CYGWIN_EXEC`. From there:

    path.h:248        iscygexec()  = mount_flags & MOUNT_CYGWIN_EXEC   -> 0
    spawn.cc:551      set (chtype, real_path.iscygexec ())
    sigproc.cc:923    _CI_ISCYGWIN set only if need_subproc_ready      -> unset
    child_info.h:80   iscygwin()   = flag & _CI_ISCYGWIN               -> 0

    spawn.cc:597      if (!iscygwin ())
                        SetHandleInformation (parent, HANDLE_FLAG_INHERIT, 0);

That branch exists to avoid leaking a process handle into a *foreign*
program. Because the Cygwin target is misclassified as foreign, it runs
against Cygwin's own child, stripping inheritability from the handle the
child needs. `CreateProcessW` is still called with `bInheritHandles=TRUE`,
but the handle is no longer inheritable, so it is not placed in the child's
handle table. The child then reads `child_info->parent` -- which arrives
intact, because the whole struct is copied by value via `si.lpReserved2` --
and uses it for `ReadProcessMemory`, which fails with ERROR_INVALID_HANDLE
and copies zero bytes.

Note the value/validity split: the handle *value* transmits as data and is
always correct; only its *validity* depended on inheritance. That is why the
symptom looks like a correct handle that does not work.

## The fix

    --- a/winsup/cygwin/hookapi.cc
    +++ b/winsup/cygwin/hookapi.cc
     @@ -44,6 +44,7 @@ PEHeaderFromHModule (HMODULE hModule)
        switch (pNTHeader->FileHeader.Machine)
          {
          case IMAGE_FILE_MACHINE_AMD64:
    +     case IMAGE_FILE_MACHINE_ARM64:
            break;
          default:
            return NULL;
          }

The tree already knows this constant (`exit_process.h:76`, `uname.cc:66`,
`path.cc:4975`); `hookapi.cc` was simply never extended.

## Evidence

Measured on Windows 11 ARM64, same test binaries, only the DLL differing.
The chain was instrumented at each link, before and after:

                        before            after
    iscygwin()          0                 1
    clear branch taken  yes               no
    flags before clear  0x1 -> 0x0        0x1 (untouched)
    at CreateProcessW   0x0               0x1  (HANDLE_FLAG_INHERIT set)
    child handle table  absent            present
    result              err 6, done 0     exec succeeds

Isolation: the fix was applied **and an earlier mitigation removed in the
same build**, so the only exec-related change was the one case label. With
that single line, `fork`+`execv`, `fork`+`execl`, exec direct from a
non-forked process, and exec of a native (non-Cygwin) program all succeed;
`err 6` disappears; and process start, printf/malloc, signal delivery,
ctype/strtol, and a fork stress test covering waitpid, sequential forks,
pipes, nested fork and child-side heap all continue to pass.

## Blast radius: seventeen decisions across three subsystems

`iscygwin()` gates **seventeen** decisions across three files (verified by
direct enumeration):

    spawn.cc      12   564 577 594 615 626 754 771 865 869 877 882 900
    sigproc.cc     3   1044 1071 1204
    exceptions.cc  2   1063 1714

This is not confined to process spawn. `sigproc.cc:1204` is **exit-code
translation** and `exceptions.cc:1063/1714` are **signal handling after
exec** -- so the misclassification reached process spawn, signal delivery
and exit-status reporting alike.

Before the fix, every one of these took the *foreign program* branch for
every native AArch64 executable. Only `:594` produced a hard, visible
failure. The rest degraded silently. Three deserve specific mention:

* **`:882` -- the readiness handshake is skipped entirely.**

        synced = iscygwin () ? sync (pi.dwProcessId, pi.hProcess, INFINITE) : true;

  For a misclassified target `sync()` is never called and `synced` is simply
  asserted true. This is not a failure, it is a **race**: every spawn
  proceeds without waiting for the child's `subproc_ready`. That is the
  classic shape of intermittent, load-dependent breakage, and it means
  results obtained on an unfixed AArch64 build should be re-read rather than
  trusted -- including earlier results in this investigation.

* **`:900` `close_all_files (iscygwin ())`** -- file-descriptor teardown
  takes the wrong path. Not cosmetic for a shell.

* **`:877` `(mode == _P_DETACH || mode == _P_NOWAIT) && !iscygwin ()`** --
  detach/nowait handling, i.e. exactly what a shell uses for background
  jobs.

So the accurate framing is not "exec is broken on AArch64" but: **a single missing case label in a PE machine-type allowlist causes
seventeen decisions across process spawn, signal handling and exit-code
translation to take the foreign-program path for every native AArch64
executable -- of which only one produced a visible failure.**

### Four latent defects that the misclassification was masking

A per-site source classification of all seventeen (contributed by a second
reviewer, read from source, **not** dynamically tested except where noted)
identifies four sites where the wrong branch was doing real damage beyond
the exec failure:

* **`spawn.cc:577`** -- ARM64 Cygwin children were wrongly given
  `CREATE_NEW_PROCESS_GROUP`, breaking Ctrl-C delivery and job-control
  process grouping. This is user-visible and independent of the exec bug.
* **`sigproc.cc:1044`** -- `PROC_EXEC_CLEANUP` was skipped on exec.
* **`sigproc.cc:1071`** -- `record_children` was skipped, so non-reaped
  children were not passed to the exec'd process.
* **`spawn.cc:882`** -- `synced = iscygwin () ? sync (...) : true`, so the
  `subproc_ready` handshake was skipped on every spawn.

The remaining thirteen are benign or corrective for this case (`594` is the
defect itself; `1063`/`1714` are the post-exec signal path tested above at
5/5; the rest are terminal setup, console handler, `write_childpid`,
`close_all_files`, an error path, a suspend superset, native-only detach,
and exit-code retry).

**Coverage caveat, stated rather than glossed:** this classification is a
source reading. The test suite here does **not** enter most of these
branches -- it has no coverage of `close_all_files` teardown,
`_P_DETACH`/`_P_NOWAIT`, console-handler setup, terminal setup, or
`write_childpid`. A passing suite therefore says nothing about them either
way, and should not be cited as cross-validation of the classification.
## Stability after the fix

Full test suite, eleven tests, five consecutive iterations: **55/55**, every
test 5/5, no flakiness. Relevant because `:882` means some pre-fix passes
may have been racing rather than correct.
## Second-subsystem regression: signal delivery after exec

`exceptions.cc:1063/1714` gate signal handling after exec and were on the
wrong branch before the fix, so this was tested explicitly rather than
assumed. A parent forks, the child execs a target that installs a handler,
raises a signal, and exits 55 only if the handler ran:

    post-exec signal test: exec'd rung5.exe exited 55
        <-- HANDLER RAN AFTER EXEC, status translated correctly

**5/5 runs.** This also exercises `sigproc.cc:1204` exit-code translation,
since the parent must observe 55 through `WEXITSTATUS` rather than a raw
Windows status.

## Note for the patch author

The in-tree `include/a.out.h` defines only `IMAGE_FILE_MACHINE_I386` and
`IMAGE_FILE_MACHINE_AMD64`; `IMAGE_FILE_MACHINE_ARM64` (0xaa64) arrives from
`w32api/winnt.h`. This compiles and works as-is -- no additional define is
needed, and adding a duplicate one would be a mistake.

The other callers of `PEHeaderFromHModule` (the API-hooking paths) become
reachable on AArch64 with this change. That surface was examined and is
**bounded, not open**: `hookapi.cc` contains no bare opcode literal (the sole
`0x`-style constant is the allowlist case label itself), and `RedirectIAT`
works through `VirtualProtect` with `sizeof (THUNK_FUNC_TYPE)` -- type-based,
not opcode-based. Detection with `fn == NULL` merely walks import descriptors
comparing names, which is architecture-neutral; the IAT-patching path runs
only when a hook function is supplied via `cygwin_internal (CW_HOOK, ...)`.
It has still not been exercised on AArch64.
## Scope and honesty

* Verified on one AArch64 build against a small purpose-built test suite.
  No real MSYS2 program (bash, coreutils) has been run.
* No threads, job control, or signals across fork have been exercised.
* Whether other callers of `PEHeaderFromHModule` (the API-hooking paths)
  behave correctly on AArch64 once the header is accepted has NOT been
  tested. This change makes those paths reachable on AArch64 for the first
  time; that is a larger surface than exec alone and deserves its own
  review.
* The alternative hypothesis -- that `MOUNT_CYGWIN_EXEC` was unset merely
  because the test environment lacks a mount table -- was considered and
  refuted: this classification path does not consult mount flags.
* **The fix flips all seventeen branches at once, and only a handful are
  covered by tests.** Twelve purpose-built test programs exercise process
  start, printf/malloc, signals, ctype, fork (including nested, pipes and
  child-side heap), argv integrity, exec in four shapes, and post-exec
  signal delivery. That is a narrow slice. Sites such as
  `spawn.cc:900 close_all_files (iscygwin ())` and
  `spawn.cc:877` (detach/nowait) change behaviour with this fix and have no
  test. If any site was inadvertently relying on the foreign-program branch,
  that change is untested here. A per-site benign-vs-latent classification
  is in progress separately and should accompany this report.
* **Some evidence in this investigation predates the fix and was therefore
  gathered with `spawn.cc:882`'s `subproc_ready` handshake suppressed**
  (`synced = iscygwin () ? sync (...) : true`). The fork-headroom and
  argv-overlap conclusions rest on instruction-level measurements -- a store
  target address moving, and byte-for-byte argument round-trips across 40
  lengths -- rather than on timing-sensitive behaviour: the stack-headroom finding is a
  static store target read from the linked image, and the argv finding is
  parent-side string handling that runs before any spawn. Both occur before
  `CreateProcess`, so the barrier's state cannot reach them. This was
  re-derived independently by a second reviewer rather than accepted from
  the author. The caveat is real but bounded to timing-sensitive claims,
  and neither of these is one.