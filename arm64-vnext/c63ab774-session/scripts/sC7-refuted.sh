#!/bin/bash
E=/mnt/c/Users/crutkasLocal/.copilot/session-state/c63ab774-a023-4e57-9bc4-53f727507ada/files/evidence
{
echo "# ARM64 vNext -- STRUCT/ABI LEAD TESTED AND REFUTED (session c63ab774)"
echo "# $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo
echo "## HYPOTHESIS: a C++/assembly struct-offset mismatch makes a consumer read"
echo "## a function pointer at +0x0C and branch to 0xFFFFFFFF00000000."
echo "## REFUTED. The layouts match exactly."
echo
echo "  struct dll_info          LP64 off   LoadDLLprime emits          off"
echo "  UINT_PTR load_state;         0      .quad _std_dll_init          0"
echo "  HANDLE   handle;             8      .quad no_resolve_on_fork     8"
echo "  LONG     here;              16      .long -1                    16"
echo "    (pad 20..23)                      .balign 8 -> pads 20..23"
echo "  void   (*init)();           24      .quad init_also             24"
echo "  WCHAR    name[];            32      UTF-16 name                 32"
echo "  => IDENTICAL, no 4-byte shift."
echo
echo "  struct func_info         LP64 off   aarch64 thunk payload       off"
echo "  struct dll_info *dll;        0      2: .quad .<dll>_info         0"
echo "  LONG decoration;             8      .hword notimp / .hword err   8"
echo "    (pad 12..15)                      .hword 0 / .hword 0         12"
echo "  UINT_PTR func_addr;         16      3: .quad 1b                 16"
echo "  char name[];                24      4: .asciz \"<name>\"          24"
echo "  => IDENTICAL, and the source carries static_asserts for 0/8/16/24."
echo
echo "## WHY THE +0x0C OBSERVATION IS NOT DIAGNOSTIC"
echo "  +0x08 handle = 0            -> 00 00 00 00 00 00 00 00"
echo "  +0x10 here   = .long -1     -> FF FF FF FF"
echo "  ANY 8-byte window starting at +0x0C therefore reads 0xFFFFFFFF00000000."
echo "  That is a property of the DATA, not evidence that a consumer reads there."
echo "  The reporter's own disclosure that this byte pattern occurs 13 times in"
echo "  .data points the same way: the value is common, not diagnostic."
echo "  (Independence check per the new rule: that observation was taken by"
echo "  reading bytes at a virtual address with no RVA arithmetic, so it does NOT"
echo "  share the ImageBase input that invalidated my relocation work. Its"
echo "  MEASUREMENT is sound; its INTERPRETATION is unsupported.)"
echo
echo "## SECOND HYPOTHESIS I RAISED AND ALSO REFUTED: the 128-bit return ABI"
echo "  dll_chain assumes a two_addr_t (__uint128_t) comes back in x0/x1:"
echo "        dll_chain:  mov x30, x0 ; br x1"
echo "  AAPCS64 returns 128-bit integers in x0:x1, but the MICROSOFT ARM64 ABI"
echo "  returns anything over 8 bytes INDIRECTLY via a hidden pointer in x8. If"
echo "  GCC followed the MS rule, x0 would be a buffer pointer and x1 garbage --"
echo "  and 'br x1' would be an EXECUTE fault to a structured-looking value,"
echo "  which is exactly the observed signature."
echo
echo "  TESTED by compiling a 128-bit-returning function with the real cross:"
echo "      caller:  mov x0, 0x1111111111111111"
echo "               mov x1, 0x2222222222222222"
echo "               b   use"
echo "  x0/x1, no x8 anywhere. GCC uses AAPCS here, so dll_chain's assumption is"
echo "  CORRECT. std_dll_init sets ret.high=func (-> x0) and ret.low=dll->init"
echo "  (-> x1); dll_chain sets x30=func and branches to dll->init. Sound."
echo
echo "## RUNNING TALLY OF ELIMINATED CAUSES FOR THE dll_entry CRASH"
echo "  1. stale autoload thunk pointers    -- REFUTED (all 424 quads relocated)"
echo "  2. struct dll_info layout mismatch  -- REFUTED (exact match)"
echo "  3. struct func_info layout mismatch -- REFUTED (exact match + asserts)"
echo "  4. 128-bit return ABI mismatch      -- REFUTED (x0/x1 confirmed)"
echo "  5. TEB register (tpidr_el0 vs x18)  -- WAS REAL, FIXED, crash persisted"
echo "  The cause remains UNKNOWN. These are eliminations, not a diagnosis."
echo
echo "## STATUS"
echo "  Nothing has executed beyond the loader. No user code has run."
} > $E/struct-abi-refuted.txt
head -12 $E/struct-abi-refuted.txt
