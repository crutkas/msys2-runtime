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
  AARCH64_PSEUDO_RELOC_INVALID_PAGE_INSTRUCTION,
  AARCH64_PSEUDO_RELOC_INVALID_PAGE_OFFSET_INSTRUCTION,
  AARCH64_PSEUDO_RELOC_REGISTER_MISMATCH,
  AARCH64_PSEUDO_RELOC_ADDRESS_OVERFLOW,
  AARCH64_PSEUDO_RELOC_OUT_OF_RANGE,
  AARCH64_PSEUDO_RELOC_MISALIGNED_PAGE_OFFSET
};

enum aarch64_pseudo_reloc_kind
{
  AARCH64_PSEUDO_RELOC_NONE,
  AARCH64_PSEUDO_RELOC_ADD,
  AARCH64_PSEUDO_RELOC_LOAD_STORE
};

struct aarch64_pseudo_reloc_result
{
  uint32_t page_instruction;
  uint32_t page_offset_instruction;
  aarch64_pseudo_reloc_kind kind;
};

static inline bool
aarch64_is_adrp (uint32_t instruction)
{
  return (instruction & 0x9f000000U) == 0x90000000U;
}

static inline aarch64_pseudo_reloc_kind
aarch64_page_offset_kind (uint32_t instruction)
{
  /* A PAGEOFFSET_12A address must be formed by a 64-bit ADD (immediate)
     without the optional 12-bit shift. */
  if ((instruction & 0xffc00000U) == 0x91000000U)
    return AARCH64_PSEUDO_RELOC_ADD;

  /* Load/store register (unsigned immediate), including valid SIMD/FP
     forms. */
  if ((instruction & 0x3b000000U) == 0x39000000U)
    {
      unsigned int size = instruction >> 30;
      unsigned int opc = (instruction >> 22) & 0x3U;
      bool simd = instruction & 0x04000000U;

      if (opc <= 1
	  || (!simd && ((opc == 2 && size <= 2)
			|| (opc == 3 && size <= 1)))
	  || (simd && size == 0 && opc >= 2))
	return AARCH64_PSEUDO_RELOC_LOAD_STORE;
    }

  return AARCH64_PSEUDO_RELOC_NONE;
}

static inline unsigned int
aarch64_page_register (uint32_t instruction)
{
  return instruction & 0x1fU;
}

static inline unsigned int
aarch64_page_offset_base_register (uint32_t instruction)
{
  return (instruction >> 5) & 0x1fU;
}

static inline intptr_t
aarch64_pseudo_reloc_addend (uint32_t instruction)
{
  uint32_t encoded = ((instruction >> 29) & 0x3U)
		     | ((instruction >> 3) & 0x1ffffcU);

  /* GNU PE auto-import leaves the original signed byte addend in the
     PAGEBASE_REL21 immediate.  It is not a page displacement until the
     runtime relocator rewrites the instruction. */
  intptr_t addend = encoded;
  if (encoded & 0x100000U)
    addend -= 0x200000;
  return addend;
}

static inline aarch64_pseudo_reloc_status
aarch64_add_import_addend (uintptr_t imported_address, intptr_t addend,
			   uintptr_t *target_address)
{
  if (addend < 0)
    {
      uintptr_t distance = (uintptr_t) -addend;
      if (imported_address < distance)
	return AARCH64_PSEUDO_RELOC_ADDRESS_OVERFLOW;
      *target_address = imported_address - distance;
    }
  else
    {
      uintptr_t distance = (uintptr_t) addend;
      if (UINTPTR_MAX - imported_address < distance)
	return AARCH64_PSEUDO_RELOC_ADDRESS_OVERFLOW;
      *target_address = imported_address + distance;
    }
  return AARCH64_PSEUDO_RELOC_OK;
}

static inline aarch64_pseudo_reloc_status
aarch64_encode_adrp (uint32_t *instruction, uintptr_t relocation_address,
		     uintptr_t target_address)
{
  if (!aarch64_is_adrp (*instruction))
    return AARCH64_PSEUDO_RELOC_INVALID_PAGE_INSTRUCTION;

  uintptr_t relocation_page = relocation_address >> 12;
  uintptr_t target_page = target_address >> 12;
  intptr_t page_delta;

  if (target_page >= relocation_page)
    {
      uintptr_t distance = target_page - relocation_page;
      if (distance >= (uintptr_t) 1 << 20)
	return AARCH64_PSEUDO_RELOC_OUT_OF_RANGE;
      page_delta = (intptr_t) distance;
    }
  else
    {
      uintptr_t distance = relocation_page - target_page;
      if (distance > (uintptr_t) 1 << 20)
	return AARCH64_PSEUDO_RELOC_OUT_OF_RANGE;
      page_delta = -(intptr_t) distance;
    }

  uint32_t immediate = (uint32_t) page_delta & 0x1fffffU;
  *instruction &= ~0x60ffffe0U;
  *instruction |= (immediate & 0x3U) << 29;
  *instruction |= (immediate & 0x1ffffcU) << 3;
  return AARCH64_PSEUDO_RELOC_OK;
}

static inline unsigned int
aarch64_load_store_scale (uint32_t instruction)
{
  if ((instruction & 0xff800000U) == 0x3d800000U)
    return 4;
  return instruction >> 30;
}

static inline aarch64_pseudo_reloc_status
aarch64_relocate_pseudo_pair (aarch64_pseudo_reloc_result *result,
			      uint32_t page_instruction,
			      uint32_t page_offset_instruction,
			      uintptr_t page_relocation_address,
			      uintptr_t import_slot_address,
			      uintptr_t imported_address)
{
  if (!aarch64_is_adrp (page_instruction))
    return AARCH64_PSEUDO_RELOC_INVALID_PAGE_INSTRUCTION;

  aarch64_pseudo_reloc_kind kind
    = aarch64_page_offset_kind (page_offset_instruction);
  if (kind == AARCH64_PSEUDO_RELOC_NONE)
    return AARCH64_PSEUDO_RELOC_INVALID_PAGE_OFFSET_INSTRUCTION;

  unsigned int page_reg = aarch64_page_register (page_instruction);
  if (page_reg == 31
      || page_reg
	 != aarch64_page_offset_base_register (page_offset_instruction))
    return AARCH64_PSEUDO_RELOC_REGISTER_MISMATCH;
  if (kind == AARCH64_PSEUDO_RELOC_ADD
      && (aarch64_page_register (page_offset_instruction) == 31
	  || aarch64_page_register (page_offset_instruction) != page_reg))
    return AARCH64_PSEUDO_RELOC_REGISTER_MISMATCH;

  intptr_t addend = aarch64_pseudo_reloc_addend (page_instruction);
  uint32_t relocated_page = page_instruction;
  uint32_t relocated_offset = page_offset_instruction;
  aarch64_pseudo_reloc_status status;

  if (kind == AARCH64_PSEUDO_RELOC_ADD && addend == 0)
    {
      /* Materialize the imported address through its in-image IAT slot.
	 This remains encodable when the provider DLL is more than 4 GiB from
	 the importing image. */
      if (import_slot_address & 0x7U)
	return AARCH64_PSEUDO_RELOC_MISALIGNED_PAGE_OFFSET;

      status = aarch64_encode_adrp (&relocated_page,
				    page_relocation_address,
				    import_slot_address);
      if (status != AARCH64_PSEUDO_RELOC_OK)
	return status;

      uint32_t scaled_offset
	= (uint32_t) ((import_slot_address & 0xfffU) >> 3);
      relocated_offset = 0xf9400000U
			 | (scaled_offset << 10)
			 | (page_offset_instruction & 0x3ffU);
    }
  else
    {
      uintptr_t target_address;
      status = aarch64_add_import_addend (imported_address, addend,
					  &target_address);
      if (status != AARCH64_PSEUDO_RELOC_OK)
	return status;

      status = aarch64_encode_adrp (&relocated_page,
				    page_relocation_address,
				    target_address);
      if (status != AARCH64_PSEUDO_RELOC_OK)
	return status;

      uint32_t page_offset = (uint32_t) (target_address & 0xfffU);
      if (kind == AARCH64_PSEUDO_RELOC_ADD)
	{
	  relocated_offset &= ~0x003ffc00U;
	  relocated_offset |= page_offset << 10;
	}
      else
	{
	  unsigned int scale
	    = aarch64_load_store_scale (page_offset_instruction);
	  uint32_t linked_offset
	    = (page_offset_instruction >> 10) & 0xfffU;
	  if (linked_offset > (0xfffU >> scale))
	    return AARCH64_PSEUDO_RELOC_INVALID_PAGE_OFFSET_INSTRUCTION;
	  if (page_offset & (((uint32_t) 1 << scale) - 1))
	    return AARCH64_PSEUDO_RELOC_MISALIGNED_PAGE_OFFSET;
	  relocated_offset &= ~0x003ffc00U;
	  relocated_offset |= (page_offset >> scale) << 10;
	}
    }

  result->page_instruction = relocated_page;
  result->page_offset_instruction = relocated_offset;
  result->kind = kind;
  return AARCH64_PSEUDO_RELOC_OK;
}

#endif /* _AARCH64_PSEUDO_RELOC_H */
