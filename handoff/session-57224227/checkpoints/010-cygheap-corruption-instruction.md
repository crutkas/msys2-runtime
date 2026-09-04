<overview>
This session is the read-only "defects investigator" (Copilot session `57224227`) in a multi-session ARM64 vNext programme making the MSYS2 runtime (`msys-2.0.dll`) run as a genuinely native Windows ARM64 toolchain (layer 1 for Git-for-Windows on ARM64). The runtime-tree owner that makes ALL source edits and runs ALL dynamic instrumentation on real Windows-on-ARM64 hardware is session `c63ab774-a023-4e57-9bc4-53f727507ada`; this session performs local cross-compile/disassemble/DWARF-inspect/static-analysis ONLY (never edits source, never runs binaries, never commits/pushes/PRs), reporting MEASURED/DERIVED/PRESUMED findings via `send_session_message`. The sole active focus is a cygheap chain-head corruption bug that — as of this segment — has been fully ROOT-CAUSED by c63ab774 to a named instruction.
</overview>

<history>
1. **Continued the cygheap-corruption hunt with c63ab774** (bug: a single transient 8-byte store writes the main thread's TEB `0x8000274000` into `cygheap+8` == `StackBase+8` == `cygheap->chain`, poisoning one chain entry's `prev` during startup in every process incl. non-forking rung9).
   - Reported my prior four-vector static negative had a gap: it searched for the TEB as a stored *value* but not the shape-sibling (a store TO `[mov-copy-of-x18, #8]`, writing the NT_TIB.StackBase field).
   - Ran the corrected TEB-field-write scan: exactly 3 sites (pthread_wrapper, create_new_main_thread_stack, dll_crt0.cc:879), all legit `teb->Tib.StackBase = <computed>`, none storing the TEB, dll_crt0_1 one fork-gated. Recorded `teb-field-write-scan-corrected`.

2. **Ran the last attach-adjacent msys surface scan** (`cygthread::stub` + CYGHEAP_STORAGE_LOW).
   - stub clean (only correct `ldr [x18,#8]`→`_cygtls` idiom); `0x800000000` materialized 3× image-wide, all value/VirtualAlloc-arg, never a store base. Recorded `cygthread-stub-and-cygheaplow-scan`. Reported msys static surface exhausted on 4 axes; elevated the fixed-cygheap-base-at-main-StackBase as a contributing factor.

3. **Accepted c63ab774's correction of my cross-thread framing.** Both operands (value=main TEB, address=main StackBase+8) belong to the MAIN thread; the bug is a pure single-thread direction inversion `*(StackBase+8) = TEB` vs correct `StackBase = *(TEB+8)`. Retracted my "crosses two threads" framing. Recorded `crossthread-framing-retracted`.

4. **Turned c63ab774's relocation near-miss into a static root cause.** It moved CYGHEAP_STORAGE_LOW alone → runtime aborted early (3-entry chain vs baseline 39 = died before corruption; a false positive it self-caught). I established from memory_layout.h that `0x800000000` is a SHARED partition boundary (`CYGHEAP_STORAGE_LOW == THREAD_STORAGE_HIGH`; `CYGHEAP_STORAGE_HIGH == USERHEAP_START`) and reframed the aliasing as by-design, not coincidence. Recorded `cygheap-relocation-is-shared-boundary`.

5. **Iterated the sealed 4-line conclusion with c63ab774 through several corrections**, each verified against primary source before ratifying into checkpoint 011:
   - Amended line 1 "KNOWN" → "DERIVED, NOT OBSERVED" (c63ab774's catch that it over-claimed in favor of its own inference). Recorded `sealed-conclusion-line1-amended`.
   - Verified c63ab774's "exact by construction" upgrade of the aliasing (StackBase == THREAD_STORAGE_HIGH iff real_size==stacksize; measured 2MB reserve → equal). Recorded `aliasing-exact-by-construction-verified`.
   - Verified/ratified c63ab774's self-correction that the EXECUTED path is `_alloc` (MEM_TOP_DOWN ceiling), NOT `_alloc_old` (the `current` seed) — confirmed via wincap.cc (`has_extended_mem_api:true` from wincap_10_1803). Marked the seed derivation WITHDRAWN.

6. **THE RESOLUTION (final, in-flight at compaction): c63ab774 NAMED THE INSTRUCTION**, falsifying 3 of our 4 sealed lines.
   - The store is in `_dll_crt0`: `str x4,[sp,#24]` at RVA 0x6CD8, where `x4 = x18` (TEB) and `[sp,#24] = (StackBase-16)+24 = StackBase+8 = cygheap->chain`. It is an ordinary COMPILER SPILL of the TEB (live across a `VirtualFree` call), NOT a deliberate TEB store — so all four scans (mine and its) hunted a shape that doesn't exist.
   - **I VERIFIED it against the shipped DLL**: hand-decoded `f9000fe4` = `str x4,[sp,#24]`; confirmed containing function `_dll_crt0` (RVA 0x6C84); confirmed `mov x4,x18` at 0x6CC8, x4 not redefined before the store.
   - **I demonstrated my own scan's defect**: a corrected vector-2 detector found 18 TEB-spill sites including 0x6CD8; my original "159 sites, ALL redefine, ZERO carriers" was a false-negative from a broken redef detector (it treated a *read* of xN as a redefinition).
   - **I verified the CAUSE from source** (dcrt0.cc:1046-1064): the x86_64 arm does `subq $32,%rsp` (documented as shadow space but also provides headroom); the aarch64 arm drops the subtraction with comment "Windows ARM64 has no shadow space, so unlike x86_64 nothing has to be subtracted here" — true about shadow space, but the subtraction's second undocumented purpose was headroom. With `sp = StackBase-16` and AArch64 spilling at positive offsets, the +24 spill lands at cygheap+8.
   - Was about to rewrite checkpoint 011's sealed conclusion (viewing lines 325-372) when compaction occurred.
</history>

<work_done>
Files updated (session-state only — ZERO source edits, entirely read-only):
- `checkpoints/011-emutls-negative-mmap-correction-allocator-clean.md` — active checkpoint. Added "Result K" (TEB breakthrough + four measured negatives + relocation experiment + shared-boundary root cause + sealed 4-line conclusion), iteratively amended through this segment (line 1 hedge, line 3 exact-by-construction corrected to `_alloc` path). **NOT YET UPDATED for the final resolution (named instruction).**
- Scratch scripts created and DELETED this segment (all cleaned; only `rd.sh` persists in files/): tebwrite.sh, tebwrite2.sh, tebfield.sh, findfn.sh, findfn2.sh, stubscan.sh, lowscan.sh, storecheck.sh, vec2fix.sh.

Todos DB: 45 rows (44 done + 1 blocked `x86_64-build-verify`). This segment added: teb-field-write-scan-corrected, cygthread-stub-and-cygheaplow-scan, crossthread-framing-retracted, cygheap-relocation-is-shared-boundary, sealed-conclusion-line1-amended, aliasing-exact-by-construction-verified.

Work completed:
- [x] Corrected TEB-field-write scan (3 legit sites).
- [x] cygthread::stub + CYGHEAP_STORAGE_LOW scan (clean).
- [x] Cross-thread framing retracted; single-thread inversion accepted.
- [x] Relocation breakage root-caused to shared partition boundary.
- [x] Aliasing exact-by-construction verified, corrected to executed `_alloc` path.
- [x] **VERIFIED c63ab774's named instruction** (str x4,[sp,#24] @ 0x6CD8 in _dll_crt0) against shipped DLL; hand-decoded the opcode.
- [x] **Demonstrated my scan's redef-detector defect** (corrected scan finds 18 spill sites incl. the culprit).
- [x] **Verified the CAUSE** from dcrt0.cc:1046-1064 (dropped `subq $32,%rsp` headroom on the aarch64 arm).
- [ ] **NOT DONE: rewrite checkpoint 011 sealed conclusion** to supersede lines 1/2/4 with the named instruction and root cause (line 3 survives, now load-bearing). In-flight at compaction.
- [ ] **NOT DONE: reply to c63ab774** confirming verification of the store, the scan defect, and the cause.
</work_done>

<technical_details>
- **THE RESOLVED BUG (ROOT CAUSE, verified):** In `_dll_crt0` (dcrt0.cc:1028), after moving the main thread stack, the aarch64 inline-asm arm sets `sp = stackaddr` where `stackaddr = StackBase-16` (from `create_new_main_thread_stack` returning `allocationbase + stacksize - 16`, dcrt0.cc via create_posix_thread.cc:276). The compiler-generated body then calls `VirtualFree(NtCurrentTeb()->DeallocationStack,...)` (dcrt0.cc:1067) and keeps the TEB (`NtCurrentTeb()` = `mov x4,x18`) live across the call for the subsequent `NtCurrentTeb()->DeallocationStack = allocationbase` (l1068). It SPILLS x4 to `[sp,#24]`. Since `sp = StackBase-16`, `[sp,#24] = StackBase+8 = cygheap+8 = cygheap->chain`. **It is an incidental compiler spill; the spilled value's identity (TEB) is coincidental — any local live across that call would corrupt the same slot.**
- **THE STORE (verified from shipped DLL, hand-decoded):**
  ```
  180046cc0: 9100001f  mov sp, x0          ; sp = StackBase-16
  180046cc4: 910003fd  mov x29, sp
  180046cc8: aa1203e4  mov x4, x18         ; x4 = TEB
  180046ccc: f94a3c80  ldr x0,[x4,#5240]   ; READS x4 (not a redef)
  180046cd0: 52900002  mov w2,#0x8000
  180046cd4: d2800001  mov x1,#0
  180046cd8: f9000fe4  str x4,[sp,#24]     ; <-- THE STORE (RVA 0x6CD8)
  180046cdc: 94070c7d  bl VirtualFree
  180046ce0: f9400fe4  ldr x4,[sp,#24]     ; reload after call
  ```
  `f9000fe4` decodes: STR(imm,64) size=11 opc=00, imm12=0x003 scaled×8=24, Rn=31(sp), Rt=4 → `str x4,[sp,#24]`. Containing function `_dll_crt0` @ RVA 0x6C84.
- **THE CAUSE (source, dcrt0.cc:1046-1064):** x86_64 arm = `movq stackaddr,%rsp; movq %rsp,%rbp; subq $32,%rsp`. aarch64 arm = `mov sp,%[ADDR]; mov x29,sp` (NO subtraction). Comment l1056-1057: "Windows ARM64 has no shadow space, so unlike x86_64 nothing has to be subtracted here." The premise (no shadow space) is true, but the `subq $32` had a SECOND undocumented purpose: headroom below sp. x86_64 addresses locals at negative offsets from rbp; AArch64 spills at positive offsets from sp — so with sp=StackBase-16 the +24 spill overruns into the cygheap.
- **WHY ALL 4 SCANS WERE BLIND (correctly scoped, wrong question):** every vector hunted for code that stores the TEB *deliberately*. (a) `str x18` as source → store is `str x4` (a copy). (b) base=copy-of-x18 → base is `sp`. (c) base=const 0x800000000 → base is `sp`. (d) mov-x18→str-xN → THIS pattern matched, but my redef detector was DEFECTIVE (counted a read `ldr x0,[x4,#5240]` as a redefinition of x4), yielding false "ALL redefine, ZERO carriers." **Corrected detector finds 18 spill sites** (mov xN,x18 → str xN,[sp,#…] with no redef), incl. 0x6CD8.
- **WHAT SURVIVES:** Only sealed line 3 (the aliasing) — and it's now LOAD-BEARING: the exact-by-construction `StackBase ≡ cygheap base ≡ 0x800000000` is precisely why a 16-byte stack overrun lands on `cygheap->chain` rather than harmless slack. Lines 1 (DERIVED single-thread inversion), 2 (origin "not msys code"), 4 (instruction unnamed) are FALSIFIED — the store IS msys-compiled code, it's a spill not an inversion, and it's now named.
- **META LESSON (c63ab774's, accepted):** a derivation matching every measured datum can still name the wrong mechanism. Our "DERIVED, NOT OBSERVED" hedge protected the reader but not the conclusion. The reframed inversion mechanism was wrong; the incidental-spill mechanism is right.
- **HONEST LIMIT (c63ab774's):** store proven present + correctly landing; the FIX (restore a subtraction / add headroom) is NOT yet demonstrated — not rebuilt, rungs not re-run.
- **Aliasing exact-by-construction (executed `_alloc` path):** wincap `has_extended_mem_api:true` from wincap_10_1803 (wincap.cc:131/144) onward incl. Win11 ARM64 → `alloc_func=&_alloc` (create_posix_thread.cc:232). `_alloc` (l142-179) uses `VirtualAlloc2(MEM_RESERVE|MEM_TOP_DOWN)` with `thread_req={THREAD_STORAGE_LOW, THREAD_STORAGE_HIGH-1, THREAD_STACK_SLOT}`; first empty-arena alloc → `allocationbase = THREAD_STORAGE_HIGH - real_size`; l274 `StackBase = base + stacksize == THREAD_STORAGE_HIGH iff real_size==stacksize`. real_size=roundup2(reserve,1MB); stacksize=roundup2(reserve,64KB); measured 2MB → both 0x200000, equal.
- **Environment/quirks (binding):** objdump/nm/gcc prefix `/root/xc/inst/bin/aarch64-pc-cygwin-*`; cannot EXECUTE aarch64 binaries in WSL. Disasm target `/root/xc/w-link/bld/winsup/cygwin/new-msys-2.0.dll`. Source READ-ONLY `/root/xc/w-defects/winsup/cygwin`. `/tmp/dll.dis` does NOT persist across WSL calls — regenerate objdump in the same command. PowerShell→WSL quoting mangles inline `bash -c` with `$VAR`/awk/commas — write a `.sh` into `files/` via `create`, then `wsl -d Ubuntu bash -c "sed -i 's/\r//' /mnt/c/.../x.sh; bash /mnt/c/.../x.sh"`. gawk 5.2.1 supports `match(s,re,arr)`. Do NOT touch `/root/xc/inst`, `/root/xc/runtime`, `/root/xc/bld`, `/root/xc/w-autoload`, `/root/xc/w-gendef`, or the Windows worktree.
- **METHOD RULES (binding):** non-match is never absence (open the file); measure what the compiler/linker emits; echo-to-transcript is not persistence; distinguish MEASURED/DERIVED/PRESUMED; a CORRECTION IS A CLAIM (re-derive from primary source); NEVER write x18 (read TEB via x18, never tpidr_el0=0 on Windows); LSE atomics unavailable; a readback/verification check must compare against what was WRITTEN, not merely test non-zero; the defect is usually in the CHECK, not the mechanism (proven 3× this segment across both sessions).
</technical_details>

<important_files>
- `C:\Users\crutkasLocal\.copilot\session-state\57224227-53ba-4c06-95b3-0ae9d9058bd5\checkpoints\011-emutls-negative-mmap-correction-allocator-clean.md`
  - The active checkpoint. Result K + sealed 4-line conclusion at ~lines 328-371. **MUST be rewritten** to supersede lines 1/2/4 with the named instruction (str x4,[sp,#24] @0x6CD8, incidental spill) and the dropped-`subq $32` cause; keep line 3 (survives, load-bearing). c63ab774 explicitly asked that this propagate fast because the original is now actively misleading.
- `files\rd.sh` — persistent numbered-line-range reader. Invoke: `wsl -d Ubuntu bash -c 'bash /mnt/c/Users/crutkasLocal/.copilot/session-state/57224227-53ba-4c06-95b3-0ae9d9058bd5/files/rd.sh FILE START END'` (reads from `/root/xc/w-defects/winsup/cygwin`). KEEP.
- `/root/xc/w-defects/winsup/cygwin/dcrt0.cc` (READ-ONLY) — **THE ROOT CAUSE SITE.** `_dll_crt0`@1028; aarch64 stack-move asm@1058-1061 (dropped subtraction); shadow-space comment@1056-1057; `VirtualFree(NtCurrentTeb()->DeallocationStack)`@1067; `DeallocationStack = allocationbase`@1068. Also dll_crt0_1 victim-birth path context.
- `/root/xc/w-defects/winsup/cygwin/create_posix_thread.cc` (READ-ONLY) — `_alloc`@142-179 (executed path, MEM_TOP_DOWN, thread_req@144-147); `_alloc_old`@181-228 (seed path, NOT executed); thread_allocator ctor@230; alloc_func select@232; create_new_main_thread_stack@242 (StackBase=base+stacksize@274, returns base+stacksize-16@276).
- `/root/xc/w-defects/winsup/cygwin/local_includes/memory_layout.h` (READ-ONLY) — the contiguous partition: THREAD_STORAGE_LOW/HIGH@34-35 (HIGH=0x800000000); CYGHEAP_STORAGE_LOW/INITIAL/HIGH@39-41 (LOW=0x800000000==THREAD_HIGH); USERHEAP_START@47 (=0xa00000000==CYGHEAP_HIGH).
- `/root/xc/w-defects/winsup/cygwin/wincap.cc` (READ-ONLY) — has_extended_mem_api:false for 5 oldest entries, true from wincap_10_1803@131/144 onward (proves executed path is `_alloc`).
- `/root/xc/w-link/bld/winsup/cygwin/new-msys-2.0.dll` (READ-ONLY artifact) — disasm target; `_dll_crt0`@0x6C84, the store@0x6CD8. Regenerate `/tmp/dll.dis` each WSL call.
</important_files>

<next_steps>
Immediate next steps (in-flight at compaction):
1. **Rewrite checkpoint 011's sealed conclusion** (lines ~328-371). Supersede: line 1 → the named instruction `str x4,[sp,#24]` @ RVA 0x6CD8 in `_dll_crt0`, an incidental compiler spill of the TEB (live across VirtualFree), NOT a deliberate store/inversion; line 2 → origin IS msys-compiled code (falsified — the "not in msys" negative was correct-scope but wrong-question); line 4 → instruction NAMED. Keep line 3 (aliasing survives, now load-bearing: explains why the 16-byte overrun is destructive). Add CAUSE: dropped `subq $32,%rsp` headroom on the aarch64 arm (dcrt0.cc:1058-1061), comment addresses shadow space but the subtraction's second purpose was headroom. Add my scan-defect note (redef detector counted reads as redefs; corrected scan = 18 spill sites). Mark this as SUPERSEDING the prior Result K seal.
2. **Reply to c63ab774** confirming: (a) store verified from shipped DLL with hand-decode; (b) my redef-detector defect demonstrated (18 spill sites, corrected scan); (c) cause verified from dcrt0.cc:1046-1064; (d) agree line 3 survives and is load-bearing; (e) note the honest limit — fix (restore headroom/subtraction) NOT yet demonstrated (c63ab774 hasn't rebuilt/re-run).
3. Record a todo (e.g. `instruction-named-root-cause`) capturing the resolution and superseding the derived-inversion todos.

Then: no further static work — the bug is root-caused. The remaining open item is the FIX (add an AArch64 stack subtraction/headroom in dcrt0.cc:1058-1061) which is c63ab774's to implement/build/test (this session cannot edit source or run binaries). The 1 blocked todo `x86_64-build-verify` still needs a Windows-host session + coordinator go/no-go.

Constraints (binding): read-only, edit no source, report to c63ab774 (coordinator when programme-level), measure don't assume, re-derive corrections from primary source, never claim a product PASS.
</next_steps>