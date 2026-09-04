#!/bin/bash
E=/mnt/c/Users/crutkasLocal/.copilot/session-state/c63ab774-a023-4e57-9bc4-53f727507ada/files/evidence
{
echo "# NARROWED: cygheap->chain IS CLOBBERED PART-WAY THROUGH EARLY INIT."
echo "# Three hypotheses killed, including my own best one."
echo "# $(date -u +%Y-%m-%dT%H:%M:%SZ)   session c63ab774"
echo
echo "## THE NEW DATUM: WHAT SITS IMMEDIATELY BELOW THE DEEPEST CHAIN ENTRY"
echo "  Dumped memory around the deepest chain entry in a NON-FORKING process:"
echo
echo "   0x8000068C0  00 00 00 00 00 00 00 00-B0 50 00 00 08 00 00 00"
echo "   0x8000068D0  01 00 00 00 00 00 00 00-00 00 00 00 00 00 00 00"
echo "   0x8000068E0  63 72 75 74 6B 61 73 4C-6F 63 61 6C 00 00 00 00  |crutkasLocal....|"
echo "   0x8000068F0  06 00 00 00 00 00 00 00-00 A0 2C 00 80 00 00 00  <== ENTRY, prev wild"
echo "   0x800006900  03 00 00 00 ...                                   (ce->type = 3)"
echo
echo "  THE ALLOCATION IMMEDIATELY BELOW THE DEEPEST CHAIN ENTRY IS THE USERNAME"
echo "  STRING. That comes from cygheap->user.init(), called in setup_cygheap()"
echo "  immediately after cygheap_init(), via cstrdup -> cmalloc. SO IT IS A"
echo "  cmalloc'd ALLOCATION AND IT SHOULD BE ON THE CHAIN. IT IS NOT -- the"
echo "  chain's deepest entry is ABOVE it."
echo
echo "  CONCLUSION, AND IT IS TIGHTER THAN THE PREVIOUS ONE:"
echo "  cygheap->chain WAS CLOBBERED BETWEEN THE USERNAME ALLOCATION AND THE"
echo "  NEXT ONE. The next _cmalloc then stored the clobbered value as its"
echo "  prev, permanently truncating the chain AND leaving a wild pointer as"
echo "  its terminator. Everything allocated before that moment is orphaned."
echo
echo "## THREE HYPOTHESES KILLED"
echo
echo "  1. MY OWN cygheap_dummy HYPOTHESIS -- DEAD."
echo "     I proposed that an early _cmalloc, while cygheap still points at the"
echo "     8-byte cygheap_dummy, reads chain one word past the object. It cannot"
echo "     happen silently: at that point cygheap_max is NULL, so _csbrk takes"
echo "     'nothing to do' and RETURNS NULL, so _cmalloc RETURNS NULL, and"
echo "     dll_list::alloc (dll_init.cc:350) would dereference a null d and"
echo "     CRASH. No crash occurs. Therefore no pre-cygheap_init _cmalloc runs."
echo "     A hypothesis that predicts a crash we do not observe is refuted."
echo
echo "  2. A BUFFER OVERRUN FROM THE PRECEDING ALLOCATION -- DEAD."
echo "     The username string is NULL-TERMINATED WITHIN its 16 bytes, and more"
echo "     decisively the entry's b field at +0 is INTACT (b = 6, a valid"
echo "     bucket). A linear overrun running off the end of the string would"
echo "     corrupt +0 BEFORE it reached +8. Only +8 is wrong. Not an overrun."
echo
echo "  3. A WIDE WRITE THROUGH cygheap->locale -- DEAD."
echo "     chain sits at +8, directly after locale at +0, so an oversized locale"
echo "     store would clobber it. Every write to cygheap->locale in the tree is"
echo "     an 8-byte pointer assignment (cygheap.cc:303, nlsfuncs.cc:1770/1772)."
echo "     sizeof(cygheap_locale) = sizeof(mini_cygheap) = 8, measured. There is"
echo "     no memcpy or memset targeting the cygheap header (the only memset is"
echo "     cygheap.cc:643, on threadlist). heap.cc:172 mentions cygheap_dummy but"
echo "     it is a COMMENT about strace output, not a write."
echo
echo "## WHAT REMAINS OPEN"
echo "  What writes 8 bytes at cygheap+8 between cygheap->user.init() and the"
echo "  next _cmalloc. The value is an mmap-arena pointer that varies per run,"
echo "  so the writer is storing a real, freshly-obtained address there."
echo
echo "## STATUS OF THE ARCH ARGUMENT -- STILL NOT ESTABLISHED"
echo "  I have NOT shown that x86_64 behaves differently here, and I have NOT"
echo "  identified an ARM64-specific trigger. Everything measured so far is"
echo "  arch-neutral code. It remains possible that this is an upstream defect"
echo "  that x86_64 also has and simply never trips. That would be a bigger"
echo "  finding, and it is NOT yet evidenced either way."
} > $E/cygheap-chain-narrowed.txt
wc -l $E/cygheap-chain-narrowed.txt
