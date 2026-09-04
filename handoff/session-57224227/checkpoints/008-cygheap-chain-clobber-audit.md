# 008 — cygheap->chain clobber static audit (STRAY WRITE)

## Assignment (c63ab774, coordinator-endorsed)
Chain corruption is NOT a fork bug — a never-forking process (rung8) has the same broken
chain: entry 0x8000068F0 (b=6 intact @+0), prev = wild mmap-arena addr, chain unterminated.
c63ab774 localized: the username cstrdup entry (from cygheap->user.init() → set_name →
cstrdup) is ORPHANED — not on the chain — so cygheap->chain was clobbered between the
username allocation and the next _cmalloc in setup_cygheap(). Static half: enumerate every
8-byte write to cygheap+8 (cygheap->chain) and every path between user.init() and the next
cmalloc (init_installation_root, pg.init).
c63ab774 pre-eliminated: (a) dummy pre-init _cmalloc [cygheap_max NULL → _csbrk NULL →
dll_list::alloc null-deref would crash; no crash = dead]; (b) linear overrun [b@+0 intact];
(c) wide locale write [all 8B ptr stores, sizeof(cygheap_locale)=8, no memcpy/memset].

## RESULT: allocator EXONERATED; the defect is a STRAY 8-byte WRITE
1. cygheap->chain has EXACTLY ONE writer in the whole tree: mm/cygheap.cc:398
   `cygheap->chain = rvc` (rvc always a _csbrk result). MEASURED (grep all *.cc/*.h; other
   ->chain hits are hook_chain/dll chains/rvc->prev reads).
2. _csbrk (cygheap.cc:326) returns prebrk=cygheap_max (pre-advance) → ALWAYS in-cygheap
   [0x800000000,0xa00000000) or NULL. Never an mmap pointer. MEASURED.
3. Wild prev values (0xBD102AE000, 0xDDC4F01000, 0x80002D1000, 0x8000316000, 0x8000384000)
   are all OUTSIDE the cygheap, in the MMAP arena. memory_layout.h: CYGHEAP
   [0x800000000,0xa00000000); USERHEAP [0xa00000000,..); MMAP [0x10000000000,0x700000000000).
   => An mmap value in prev@+8 CANNOT come from the allocator. STRAY WRITE. MEASURED+DERIVED.

## Full init_cygheap offset map (MEASURED from DWARF, shipped cygheap.o)
locale/lh_first 0 | chain 8 | buckets 16 | installation_root 272 | installation_root_buf 288
| installation_dir 8480 | installation_dir_buf 8496 | installation_key 16688 |
installation_key_buf 16704 | root 16744 | dom 16752 | pg 16960 | ugid_cache 17912 |
user 17944 | user_heap 18336 | shared_regions 18376 | umask 18408 | rlim_as_id 18412 |
rlim_core 18416 | console_h 18424 | cwd 18432 | fdtab 18480 | sigs 18528 | ctty 18536 |
threadlist 18544 | sthreads 18552 | pid 18556 | inode_list 18560 | hooks 18568.
sizeof(init_cygheap)=0x48A0=18592. NO field lands a store on +8 by a small offset slip;
buckets[0]@+16 is adjacent but does not overlap +8.

## setup_cygheap window checked (MEASURED)
- pg.init() (uinfo.cc:585): init_pwd/init_grp (passwd.cc:50, grp.cc:56) only set a function
  pointer + elem size. ZERO cygheap alloc, ZERO header write. Not the clobber.
- init_installation_root() (cygheap.cc:161): writes ONLY installation_root_buf(+288),
  installation_dir_buf(+8496), installation_key_buf(+16704) + UNICODE_STRING headers — all
  far above +8. memmoves stay within installation_root_buf. reg_key is #ifndef __MSYS__
  (excluded on MSYS).
- user.init() (uinfo.cc:39): set_name→cstrdup = the username entry; sec_user_nih (uinfo.cc:90)
  does NOT allocate from cygheap (grep sec/ for cmalloc-family = empty).

## Timing clue (handed to c63ab774 for dynamic confirmation)
mmap arena (VirtualAlloc(NULL,...) at heap.cc:121, malloc.cc:1670/1676, mmap.cc:1611) is
created in memory_init()/user_heap.init(), which run AT/AFTER dcrt0.cc:754 — AFTER
setup_cygheap() (dcrt0.cc:753). So mmap-arena addresses don't exist yet when the username
entry is allocated inside setup_cygheap. => the stray write into its prev@+8 happens LATER
than setup_cygheap (post-memory_init). Reading the entry's +8 right after setup_cygheap vs
after memory_init would pin it.

## Caution honored
Framed as "a cygheap defect observed on ARM64, arch-differential UNKNOWN." No arch-specific
trigger found; every line here is arch-neutral. NOT recorded as an ARM64 defect.

## x18 — SETTLED (per c63ab774), stand down
GetThreadContext reporting artefact for the platform-reserved register: c63ab774's healthy
non-forking rung3 capture (TEB fix demonstrably live) also shows x18=0. My "Cygwin writes x18
nowhere" made it decidable by eliminating the software explanation.

## Files (READ-ONLY, none edited)
- mm/cygheap.cc: cygheap_dummy@30, cygheap ptr@35, _csbrk@326, _cmalloc@365 (chain write@398),
  _cfree@404, cmalloc/ccalloc@461-542, set_name@614, init_tls_list@640, cygheap_init@289,
  setup_cygheap@318, init_installation_root@161
- uinfo.cc: cygheap_user::init@39 (set_name@58, sec_user_nih@90), cygheap_pwdgrp::init@585
- passwd.cc:50 init_pwd; grp.cc:56 init_grp
- local_includes/cygheap.h: init_cygheap@499 (chain@504), mini_cygheap@484, _cmalloc_entry@15
- local_includes/memory_layout.h:39-52 region constants
- dcrt0.cc:748 do_global_ctors, :753 setup_cygheap, :754 memory_init
- Built object read for DWARF: /root/xc/w-link/bld/winsup/cygwin/mm/cygheap.o
