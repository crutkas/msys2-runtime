/* aarch64_pseudo_reloc.h: AArch64 runtime pseudo-relocation helpers

   This file is part of Cygwin.

   This software is a copyrighted work licensed under the terms of the
   Cygwin license.  Please consult the file "CYGWIN_LICENSE" for
   details. */

#ifndef _AARCH64_PSEUDO_RELOC_H
#define _AARCH64_PSEUDO_RELOC_H

#include <stdint.h>

enum aarch64_pseudo_reloc_status
{
  AARCH64_PSEUDO_RELOC_OK,
  AARCH64_PSEUDO_RELOC_INVALID_INSTRUCTION,
  AARCH64_PSEUDO_RELOC_OUT_OF_RANGE
};

static inline aarch64_pseudo_reloc_status
aarch64_relocate_adrp (uint32_t *instruction, uintptr_t relocation_address,
		       uintptr_t imported_address)
{
  if ((*instruction & 0x9f000000U) != 0x90000000U)
    return AARCH64_PSEUDO_RELOC_INVALID_INSTRUCTION;

  /* GNU PE auto-import leaves the original signed byte addend in ADRP's
     immediate; it is not the instruction's final page displacement yet. */
  uint32_t encoded_addend = ((*instruction >> 29) & 0x3U)
			    | ((*instruction >> 3) & 0x1ffffcU);
  intptr_t addend = encoded_addend;
  if (encoded_addend & 0x100000U)
    addend -= 0x200000;

  const uintptr_t page_mask = ~(uintptr_t) 0xfff;
  intptr_t relocated_page = (imported_address + addend) & page_mask;
  intptr_t relocation_page = relocation_address & page_mask;
  intptr_t page_delta = (relocated_page - relocation_page) >> 12;
  if (page_delta < -(1 << 20) || page_delta >= (1 << 20))
    return AARCH64_PSEUDO_RELOC_OUT_OF_RANGE;

  uint32_t immediate = (uint32_t) page_delta & 0x1fffffU;
  *instruction &= ~0x60ffffe0U;
  *instruction |= (immediate & 0x3U) << 29;
  *instruction |= (immediate & 0x1ffffcU) << 3;
  return AARCH64_PSEUDO_RELOC_OK;
}

static inline aarch64_pseudo_reloc_status
aarch64_relocate_add (uint32_t *instruction, uintptr_t import_target,
		      uintptr_t imported_address)
{
  if ((*instruction & 0x7f400000U) != 0x11000000U)
    return AARCH64_PSEUDO_RELOC_INVALID_INSTRUCTION;

  uint32_t linked_offset = (*instruction >> 10) & 0xfffU;
  uint32_t addend = (linked_offset - (import_target & 0xfffU)) & 0xfffU;
  uint32_t relocated_offset = (imported_address + addend) & 0xfffU;

  *instruction &= ~0x003ffc00U;
  *instruction |= relocated_offset << 10;
  return AARCH64_PSEUDO_RELOC_OK;
}

#endif /* _AARCH64_PSEUDO_RELOC_H */
