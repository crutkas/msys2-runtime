#include <stdint.h>

#include "../../winsup/cygwin/local_includes/aarch64_pseudo_reloc.h"

static uint32_t
linked_adrp (intptr_t addend)
{
  uint32_t immediate = (uint32_t) addend & 0x1fffffU;

  return 0x90000000U
	 | ((immediate & 0x3U) << 29)
	 | ((immediate & 0x1ffffcU) << 3);
}

static uint32_t
linked_add (uintptr_t import_target, intptr_t addend)
{
  uint32_t offset = (import_target + addend) & 0xfffU;

  return 0x91000000U | (offset << 10);
}

static uintptr_t
decode_address (uint32_t adrp, uint32_t add, uintptr_t relocation_address)
{
  uint32_t encoded_delta = ((adrp >> 29) & 0x3U)
			   | ((adrp >> 3) & 0x1ffffcU);
  intptr_t page_delta = encoded_delta;
  if (encoded_delta & 0x100000U)
    page_delta -= 0x200000;

  intptr_t page = (relocation_address & ~(uintptr_t) 0xfff)
		  + page_delta * 0x1000;
  return page + ((add >> 10) & 0xfffU);
}

static int
check_relocation (uintptr_t relocation_address, uintptr_t import_target,
		  uintptr_t imported_address, intptr_t addend)
{
  uint32_t adrp = linked_adrp (addend);
  uint32_t add = linked_add (import_target, addend);

  if (aarch64_relocate_adrp (&adrp, relocation_address, imported_address)
      != AARCH64_PSEUDO_RELOC_OK)
    return 1;
  if (aarch64_relocate_add (&add, import_target, imported_address)
      != AARCH64_PSEUDO_RELOC_OK)
    return 2;
  if (decode_address (adrp, add, relocation_address)
      != imported_address + addend)
    return 3;
  return 0;
}

int
main ()
{
  static const struct
  {
    uintptr_t relocation_address;
    uintptr_t import_target;
    uintptr_t imported_address;
    intptr_t addend;
  } cases[] = {
    { 0x180001000, 0x180006038, 0x180045678, 0 },
    { 0x180001000, 0x180006038, 0x180045678, 1 },
    { 0x180001000, 0x180006038, 0x180045678, 0x1000 },
    { 0x180001000, 0x180006038, 0x180045678, -1 },
    { 0x180001000, 0x180006038, 0x180045678, -0x1000 },
    { 0x180001ffc, 0x180006fff, 0x180045fff, 1 },
    { 0x180002004, 0x180006000, 0x180046000, -1 },
    { 0x180001000, 0x180006038, 0x180045678, 0xfffff },
    { 0x180001000, 0x180006038, 0x180045678, -0x100000 }
  };

  for (const auto &test : cases)
    if (check_relocation (test.relocation_address, test.import_target,
			  test.imported_address, test.addend) != 0)
      return 1;

  uint32_t adrp = linked_adrp (0);
  if (aarch64_relocate_adrp (&adrp, 0x1000, 0x100001000)
      != AARCH64_PSEUDO_RELOC_OUT_OF_RANGE)
    return 2;

  adrp = 0;
  if (aarch64_relocate_adrp (&adrp, 0x1000, 0x2000)
      != AARCH64_PSEUDO_RELOC_INVALID_INSTRUCTION)
    return 3;

  uint32_t add = 0;
  if (aarch64_relocate_add (&add, 0x1000, 0x2000)
      != AARCH64_PSEUDO_RELOC_INVALID_INSTRUCTION)
    return 4;

  return 0;
}
