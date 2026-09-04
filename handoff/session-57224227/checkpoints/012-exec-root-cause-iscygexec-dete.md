<overview>
This session is the read-only "Runtime remaining defects" static-analysis lane (Copilot session `57224227`) in a multi-session ARM64 vNext programme making the MSYS2 runtime (`msys-2.0.dll`) run as a genuinely native Windows ARM64 toolchain (layer 1 for Git-for-Windows on ARM64). This session performs ONLY local cross-compile/disassemble/DWARF-inspect/static-source-analysis — it never edits source, runs binaries, commits, pushes, or PRs. The runtime-tree owner that makes all edits and runs all dynamic instrumentation on real Windows-on-ARM64 hardware is session `c63ab774-a023-4e57-9bc4-53f727507ada`; a coordinator "General Chat" session `2b2e50a5-63c5-49f9-8b89-d825396b5ff9` orchestrates. This session reports MEASURED/DERIVED/PRESUMED findings via `send_session_message` to both, and records durable findings in checkpoint 011.
</overview>

<history>
1. **All three original runtime defects reached "fixed" state before/early in this segment** (fork stack headroom, argv strcpy-overlap, exec child_copy). This segment focused almost entirely on the static root-cause investigation of the exec defect and reconciling cross-session messages.

2. **Closed the exec parent-handle transmission static trace** — established `child_info_spawn::set` (child_info.h:155) is placement-new re-running the ctor per-exec, so `parent` is re-minted fresh, not stale. Named the "dual transmission" (value crosses by-value via `lpReserved2`; validity needs OS inheritance). Reported to c63ab774.

3. **c63ab774 confirmed exec was FIXED** by making `get_parent_handle()`'s `OpenProcess` recovery reachable (dcrt0.cc:644). Measured `parent=0x19C usable=0 err=6`. I confirmed the fault-site reading from source and delivered the static boundary (why inheritance doesn't take = dynamic/below source).

4. **Coordinator flagged my disasm target stale** (`9fcc134e` = fork+argv only) and urged me to reply to coordinator messages rather than go idle. I adopted "report upward and sideways, reply briefly" discipline.

5. **Coordinator challenged my "inherit-clear breaks non-Cygwin exec" by-product claim** — I re-derived from source and RETRACTED it (the clear is deliberate hygiene; no non-Cygwin path consumes `child_info`).

6. **Investigated the fork-then-exec asymmetry** (c63ab774's question: exec-ing process is itself a forked child). Read both CreateProcess sites; both pass `bInheritHandles=TRUE`. Reached static boundary. THEN coordinator's "fork-ancestry is DEAD" (verifier's direct `execl` failed identically) SUPERSEDED this — I RETRACTED the fork-then-exec lead to c63ab774.

7. **Killed the STARTUPINFOEX/PROC_THREAD_ATTRIBUTE_HANDLE_LIST candidate** (coordinator's UNVERIFIED lead) — tree-wide grep + positive confirm: only used in fhandler/pty.cc, both exec/fork use plain STARTUPINFO. Candidate DEAD.

8. **Falsified the parent-close-window hypothesis** — read `handle_spawn` (dcrt0.cc:639-698): the `CloseHandle(parent)` at 687-694 is child-side and strictly AFTER the failing `child_copy` read at 646.

9. **Reconciled c63ab774's decisive `GetHandleInformation` measurement** (`in_table=0` — handle ABSENT from child table, upgrading my derivation). Both "stale" close-out items (non-Cygwin, leak) already reconciled on my side.

10. **Adopted coordinator's premise-tightening**: "`bInheritHandle=TRUE`" is REQUESTED not OBSERVED — must not assert the handle WAS inheritable until parent-side `GetHandleInformation` lands.

11. **Audited the mint→create window** (spawn.cc:551→660/712) as a unit — one guarded touch of `parent` (597, `if(!iscygwin())`), impersonation asymmetry REAL but INERT (`deimpersonate()` = `RevertToSelf()`, touches no handles).

12. **ROOT CAUSE FOUND (by c63ab774, dynamic)** — measured `GetHandleInformation` at CreateProcess: `flags=0x0` (NOT inheritable). Instrumented the clear: `spawn.cc:597 if(!iscygwin())` FIRES because `iscygwin()` returns 0 while spawning `rung3.exe` (an MSYS binary linked against this DLL). **This is the candidate all four parties rejected on the guard's existence without evaluating the guard's condition** — a shared miss. c63ab774 handed me the decisive static thread: **how does `MOUNT_CYGWIN_EXEC` get set** — mount-table-only (→ harness artefact, NOT ARM64 defect) or PE auto-detection (→ possible genuine ARM64 defect).

13. **IN PROGRESS: tracing `MOUNT_CYGWIN_EXEC` source.** Found: it's set two ways — the `"cygexec"` mount option (mount.cc:1118) AND programmatic `set_cygexec()` (path.h:253-266). Callers are in spawn.cc:1168-1238; the decisive one is spawn.cc:1225 `set_cygexec(hook_or_detect_cygwin(buf, NULL, subsys, hm))` — **PE auto-inspection, so NOT mount-table-only (option 2/3, not option 1)**. Was about to read `hook_or_detect_cygwin` (hookapi.cc:333) to determine if its PE parsing is architecture-dependent when compaction occurred.
</history>

<work_done>
Files updated (session-state ONLY — ZERO source edits, entirely read-only):
- `checkpoints/011-emutls-negative-mmap-correction-allocator-clean.md` — the active durable record. This segment appended extensive exec-investigation content after RESULT O: the parent-handle transmission trace, exec-fixed confirmation, stale-carried FALSIFIED, non-Cygwin RETRACTION, fork-then-exec lead + its SUPERSESSION, STARTUPINFOEX DEAD, parent-close-window FALSIFIED, (A)/(B) GetHandleInformation confirmation, premise-tightening (REQUESTED not OBSERVED), DLL hash moves, and the mint→create window audit.

Todos DB rows added this segment (all status=done): `exec-parent-handle-transmission-clean`, `exec-parent-handle-per-exec-fresh-dual-mechanism`, `correction-noncygwin-inheritclear-retracted`, `exec-startupinfoex-handlelist-candidate-DEAD`, `exec-fork-then-exec-asymmetry-static`, `exec-parent-close-window-falsified`, `exec-gethandleinfo-absent-confirms-AB`, `exec-premise-tighten-requested-not-observed`, `exec-mint-to-create-window-audit`. Todo count: 59 done, 1 blocked (`x86_64-build-verify`).

Work completed:
- [x] Exec parent-handle transmission path traced; stale-carried hypothesis FALSIFIED from source (placement-new re-mints per-exec).
- [x] Named the dual (A)/(B) transmission mechanism; confirmed by c63ab774's GetHandleInformation `in_table=0`.
- [x] RETRACTED the "non-Cygwin exec breaks" by-product claim (re-derived: deliberate hygiene, no non-Cygwin consumer).
- [x] RETRACTED the fork-then-exec asymmetry lead (superseded by measured fork-ancestry-DEAD).
- [x] STARTUPINFOEX handle-list candidate DEAD (grep + positive confirm).
- [x] Parent-close-window hypothesis FALSIFIED (close is child-side, strictly after read).
- [x] Premise-tightened "bInheritHandle=TRUE" to REQUESTED-not-OBSERVED throughout.
- [x] Mint→create window (spawn.cc:551→712) audited: one guarded touch, impersonation asymmetry inert.
- [ ] **IN PROGRESS: `MOUNT_CYGWIN_EXEC` source determination** — established it's PE-auto-detection via `hook_or_detect_cygwin` (spawn.cc:1225), NOT mount-only. Was about to read `hook_or_detect_cygwin` (hookapi.cc:333) for architecture-dependence when compaction occurred.
- [ ] Reply to c63ab774 (root-cause found, shared miss owned) and coordinator (the MOUNT_CYGWIN_EXEC read result) — NOT YET SENT.
</work_done>

<technical_details>
- **EXEC ROOT CAUSE (found by c63ab774 dynamically, being characterised statically by me):** `spawn.cc:597 SetHandleInformation(parent, HANDLE_FLAG_INHERIT, 0)` under `if(!iscygwin())` FIRES when spawning `rung3.exe` because `iscygwin()` returns 0. Chain: `iscygwin()` = `flag & _CI_ISCYGWIN` (child_info.h:80); `_CI_ISCYGWIN` set only if `need_subproc_ready` in ctor (sigproc.cc:923-927); wired to `real_path.iscygexec()` = `mount_flags & MOUNT_CYGWIN_EXEC` (path.h:248). Measured: `CLR: before-clear flags=0x1 iscygwin=0 will_clear=1; after-clear flags=0x0`; then `GetHandleInformation` at CreateProcess = `flags=0x0`; child `in_table=0 err=6`. The dup works, then Cygwin's own hygiene branch (meant for foreign programs) strips inheritance from our own handle.
- **THE DECISIVE OPEN STATIC QUESTION (c63ab774's + coordinator's, my current lane):** WHY is `MOUNT_CYGWIN_EXEC` / `iscygexec()` false for our binaries? Three possibilities: (1) mount-table-only → HARNESS ARTEFACT, not an ARM64 defect (scratch env has no mount table); (2) PE auto-detection failing on aarch64 → GENUINE ARM64 DEFECT; (3) both with cache. **MEASURED SO FAR: it is NOT option 1.** `MOUNT_CYGWIN_EXEC` is set both by the `"cygexec"` mount option (mount.cc:1118) AND programmatically via `set_cygexec()` (path.h:253-266). The exec path calls `set_cygexec(hook_or_detect_cygwin(buf, NULL, subsys, hm))` at spawn.cc:1225 — PE auto-inspection of the mapped image. So detection exists and is binary-driven.
- **NEXT READ (was in flight):** `hook_or_detect_cygwin` at hookapi.cc:333 (signature `hook_or_detect_cygwin(const char *name, const void *fn, WORD& subsys, HANDLE h)`, declared winsup.h:200). Must determine whether its PE parsing (IAT address computation, import walk looking for the Cygwin/MSYS DLL, subsystem/machine-type reads) is architecture-dependent in a way that fails for an aarch64 PE. Report MEASURED-from-source with line numbers; report plainly if it's option 1 (which would downgrade the finding). NOTE spawn.cc:1222 reads a PE offset by hard-coded byte offset `buf[0x18]|(buf[0x19]<<8)` and `subsys` is passed uninitialized (it's an out-param).
- **THE SHARED MISS (must own honestly in reply):** I recorded the `iscygwin()`-guarded inherit-clear as REJECTED. So did the verifier and c63ab774. All four read the guard's existence and reasoned "our target is Cygwin so it can't fire" WITHOUT measuring what `iscygwin()` returns. c63ab774's framing to record verbatim: "rejecting a candidate because a guard exists, without measuring what the guard evaluates to, is an inference standing in for a measurement." My "check the guard before asserting the mechanism" discipline was right in form but stopped one step short (checking a guard exists ≠ checking what it returns).
- **(A)/(B) DECOUPLING (my derivation, now the mechanism):** (A) handle value crosses unconditionally as bytes in `si.lpReserved2` (whole `child_info_spawn` copied by value, `cbReserved2=sizeof(*this)`, spawn.cc:556-557; child reads dcrt0.cc:531); (B) validity requires OS inheritance — which our own code disabled at spawn.cc:597 before CreateProcess. That's why `OpenProcess` recovery repairs it.
- **DEFECT #1 (FIXED, committed `d9369d0bf`):** cygheap chain corruption — `str x4,[sp,#24]` @ RVA 0x6CD8 in `_dll_crt0`, TEB spill landing on cygheap+8 via StackBase≡cygheap-base aliasing; fix `sub sp,sp,#0x40`.
- **DEFECT #2 (FIXED, committed `6397acaa5`):** upstream Cygwin strcpy-overlap in `dcrt0.cc quoted()` (strcpy(X,X+1) UB, exposed by NEON strcpy); fix memmove. Also corrupts exec target filenames (rung3.exe→runng3.exe→ENOENT), which masked the exec err6 symptom on pre-fix builds ("error 6 gone" was an artefact).
- **DEFECT #3 (exec, FIXED by c63ab774):** `get_parent_handle()` recovery made reachable at dcrt0.cc:644 + handle-leak close inside get_parent_handle (`HANDLE prev=parent; parent=OpenProcess(...); if(parent&&prev&&prev!=parent) CloseHandle(prev);` — closes on success only); execv/execl 77/77, 8/8 verified.
- **MEASURED DEAD candidates (six):** ch_spawn stale-handle; fork-ancestry (rung19 direct-from-main fails identically; `InheritedFromUniqueProcessId==parent_winpid` both paths); iscygwin inherit-clear as a *non-Cygwin* breakage (that by-product retracted, but the clear IS now the root cause for the Cygwin case via the wrong guard condition); STARTUPINFOEX handle-list; parent-close-window; impersonation asymmetry (inert, `deimpersonate`=`RevertToSelf`).
- **DLL hash progression (canonical `new-msys-2.0.dll`):** `9fcc134e` (fork+argv only, STALE) → `3c1cc03a` → `7be56027` → **`b9eb5eb6`** (current per c63ab774's last msg; rebuilt after probe removal, `--no-insert-timestamp` byte-reproducible) — coordinator separately cited `490ffdec` as byte-reproducible; hashes moved rapidly. My conclusions are source-derived so unaffected; re-point for any future disasm only.
- **Environment quirks (binding):** tools `/root/xc/inst/bin/aarch64-pc-cygwin-*`; cannot EXECUTE aarch64 binaries in WSL. Source READ-ONLY `/root/xc/w-defects/winsup/cygwin`. `/tmp` doesn't persist across WSL calls. PowerShell→WSL mangles inline `bash -c` with `$VAR`/awk/quotes/`|` alternation — write a `.sh` into `files/` and invoke it, OR split into simple grep commands. `files/rd.sh` reads numbered line ranges: `wsl -d Ubuntu bash -c 'bash /mnt/c/.../files/rd.sh FILE START END'` (reads from `/root/xc/w-defects/winsup/cygwin`). Checkpoint edits: the exec content is NOT at file tail — anchor edits on unique recent-line text; wrapping/whitespace can differ from what you expect (two edits failed on stale anchors this segment).
- **METHOD RULES (binding):** non-match is never absence (open the file); measure what compiler/linker emits; a CORRECTION IS A CLAIM (re-derive from primary source); distinguish MEASURED/DERIVED/PRESUMED; validate a detector against a known positive before trusting its negative; NEVER write x18 (holds TEB); LSE atomics unavailable (baseline ARMv8-A); report full labelled progression of counts; never claim a product PASS (nothing has executed on ARM64); report upward AND sideways, reply briefly rather than going idle.
</technical_details>

<important_files>
- `C:\Users\crutkasLocal\.copilot\session-state\57224227-53ba-4c06-95b3-0ae9d9058bd5\checkpoints\011-emutls-negative-mmap-correction-allocator-clean.md`
   - The active durable record. Contains sealed 4-line conclusion (lines 1/2/4 FALSIFIED, line 3 SURVIVES) and RESULTS L/M/N/O plus the entire exec-investigation appendix from this segment. Continue appending the MOUNT_CYGWIN_EXEC finding here. Anchor edits on unique recent text (e.g. "Todo: exec-mint-to-create-window-audit.").
- `/root/xc/w-defects/winsup/cygwin/spawn.cc` (READ-ONLY) — **the root-cause file.** Inherit-clear @594-598 (`if(!iscygwin())`, clears parent @597); `set(chtype,iscygexec())` @551; `si.lpReserved2=this` @556-557; CreateProcessW @656 (rung3 path), CreateProcessAsUserW @707 (setuid only); `deimpersonate()` @635; `parent_winpid=GetCurrentProcessId()` @602; **cygexec detection block @1150-1245**, decisive call `set_cygexec(hook_or_detect_cygwin(buf,NULL,subsys,hm))` @1225, PE-magic check @1219-1222.
- `/root/xc/w-defects/winsup/cygwin/hookapi.cc` (READ-ONLY) — **NEXT TO READ.** `hook_or_detect_cygwin` definition @333 — the PE-inspection routine that decides the cygexec bit. Must check for architecture-dependence in its IAT/import/subsystem parsing.
- `/root/xc/w-defects/winsup/cygwin/local_includes/path.h` (READ-ONLY) — `iscygexec()` @248 (`mount_flags & MOUNT_CYGWIN_EXEC`); `set_cygexec(bool)` @253, `set_cygexec(void*)` @260 (the auto-detect overload).
- `/root/xc/w-defects/winsup/cygwin/mount.cc` (READ-ONLY) — `"cygexec"` mount option @1118 (the mount-table source of the bit); MOUNT_CYGWIN_EXEC use @1829.
- `/root/xc/w-defects/winsup/cygwin/include/sys/mount.h` (READ-ONLY) — `MOUNT_CYGWIN_EXEC = _BIT(6)` @31.
- `/root/xc/w-defects/winsup/cygwin/local_includes/child_info.h` (READ-ONLY) — `iscygwin()` @80 (`flag & _CI_ISCYGWIN`); `_CI_ISCYGWIN=0x02` @23; `set()` placement-new @155; `_CH_EXEC=1`/`_CH_SPAWN=2` @14-15.
- `/root/xc/w-defects/winsup/cygwin/local_includes/cygheap.h` (READ-ONLY) — `deimpersonate()` @162-165 = `RevertToSelf()` (proves impersonation asymmetry inert).
- `/root/xc/w-defects/winsup/cygwin/sigproc.cc` (READ-ONLY) — `child_info` ctor @897; parent mint `DuplicateHandle(...,&parent,perms,TRUE,0)` @938; `_CI_ISCYGWIN` set iff `need_subproc_ready` @923-927.
- `/root/xc/w-defects/winsup/cygwin/dcrt0.cc` (READ-ONLY) — `get_parent_handle()` @633-637; `handle_spawn()` @639-698 (fixup guard @644, child-side parent-close @687-694); child reads lpReserved2 @531.
- `files\rd.sh` — persistent numbered-line-range reader. KEEP.
</important_files>

<next_steps>
Immediate next step (in flight at compaction): **Read `hook_or_detect_cygwin` at hookapi.cc:333** and determine whether its PE-parsing (IAT address computation, import-directory walk for the Cygwin/MSYS DLL name, subsystem/machine-type reads) is architecture-dependent in a way that misclassifies an aarch64 PE — which would make the exec root cause a GENUINE ARM64 DEFECT — versus the possibility that `iscygexec()` is simply false because the scratch environment lacks a mount table (which would make it a HARNESS ARTEFACT, not an ARM64 defect). This is THE decisive question that determines whether the finding is filable as an ARM64 runtime defect. Report MEASURED-from-source with line numbers; state plainly if it points to the harness-artefact outcome.

Then:
1. **Reply to c63ab774** — acknowledge the root cause found, OWN the shared miss honestly (I recorded the candidate REJECTED without measuring the guard's value), confirm the guard-chain from source (iscygwin←_CI_ISCYGWIN←need_subproc_ready←iscygexec←MOUNT_CYGWIN_EXEC), and report the hook_or_detect_cygwin architecture-dependence finding.
2. **Reply to coordinator (2b2e50a5)** — report the MOUNT_CYGWIN_EXEC source read as MEASURED-from-source: it is NOT mount-only (option 1); PE auto-detection exists at spawn.cc:1225 via hook_or_detect_cygwin; give the architecture-dependence verdict. Confirm the mint→create window audit's "one touch only" finish they asked for (already done: 597 is the only touch of parent).
3. **Update checkpoint 011** with the root-cause resolution, the shared-miss record (verbatim c63ab774 framing), and the MOUNT_CYGWIN_EXEC/hook_or_detect_cygwin finding.
4. Re-point disasm target note to current canonical hash (`b9eb5eb6` per c63ab774's last message).

Constraints (binding): read-only, edit no source, run no binaries; report to c63ab774 (peer) and 2b2e50a5 (coordinator); a correction is a claim (re-derive from primary source); report MEASURED vs DERIVED vs PRESUMED; the blocked `x86_64-build-verify` todo still needs a Windows-host session + coordinator go/no-go. Do NOT revive the `+8/+12` fingerprint or the fork-then-exec/stale-carried/STARTUPINFOEX candidates (all measured dead).
</next_steps>