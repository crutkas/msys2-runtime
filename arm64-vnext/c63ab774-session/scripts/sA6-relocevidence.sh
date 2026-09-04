#!/bin/bash
E=/mnt/c/Users/crutkasLocal/.copilot/session-state/c63ab774-a023-4e57-9bc4-53f727507ada/files/evidence
{
echo "# ARM64 vNext -- AUTOLOAD THUNK BASE-RELOCATION DEFECT (session c63ab774)"
echo "# $(date -u +%Y-%m-%dT%H:%M:%SZ)   measured on the linked DLL"
echo
echo "## MEASUREMENT"
echo "  section .autoload_text : RVA 0x218000, size 0x5060"
echo "  thunk entry points     : 212"
echo "  absolute 8-byte quads  : 424   (2 per thunk: info ptr @+0x30, resolved addr @+0x40)"
echo "  DIR64 fixups in image  : 17837"
echo "  DIR64 fixups in section: 48"
echo "  quads WITH  relocation : 10"
echo "  quads WITHOUT          : 414    <<<"
echo
echo "  examples missing: CheckTokenMembership @0x218030 / @0x218040,"
echo "                    CreateProcessAsUserW @0x218090 / @0x2180A0,"
echo "                    DeregisterEventSource, DecryptFileW, ..."
echo
echo "## WHY IT MATTERS"
echo "  The aarch64 thunk (autoload.cc LoadDLLfuncEx3) is:"
echo "      ldr x16, 3f      // load the resolved-address slot"
echo "      br  x16          // branch to it"
echo "    1: <loader stub>"
echo "    2: .quad .<dll>_info      // info block pointer"
echo "    3: .quad 1b               // initially points at the loader stub"
echo
echo "  Both quads are ABSOLUTE addresses. The image is ASLR-relocated at load"
echo "  time -- observed base 0x00007FFDAD3D0000 vs preferred 0x180000000 -- so"
echo "  without a DIR64 base relocation each slot still holds a PREFERRED-BASE"
echo "  address after loading. The very first call to any affected autoloaded"
echo "  function therefore branches into unmapped memory."
echo
echo "  This is consistent with the observed post-TEB-fix fault:"
echo "      0xC0000005 ACCESS_VIOLATION EXEC, PC itself invalid"
echo "  i.e. a branch to a bad code pointer rather than a null dereference."
echo
echo "## STATUS"
echo "  MEASURED, NOT YET FIXED. Root cause of the missing relocations (assembler"
echo "  emission in a custom \"wx\" section vs linker .reloc generation) is NOT yet"
echo "  established, and the exact fault value 0xFFFFFFFF00000000 is NOT yet"
echo "  fully explained by this alone. Reported as measured."
} > $E/autoload-reloc-defect.txt
cat $E/autoload-reloc-defect.txt
