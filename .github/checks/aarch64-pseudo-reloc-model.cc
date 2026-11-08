#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "../../winsup/cygwin/local_includes/aarch64_pseudo_reloc.h"

static uint32_t
linked_adrp (intptr_t addend, unsigned int reg)
{
  uint32_t immediate = (uint32_t) addend & 0x1fffffU;
  return 0x90000000U
	 | ((immediate & 0x3U) << 29)
	 | ((immediate & 0x1ffffcU) << 3)
	 | reg;
}

static uint32_t
linked_add (unsigned int destination, unsigned int base)
{
  return 0x91000000U | (base << 5) | destination;
}

static intptr_t
decode_page_delta (uint32_t instruction)
{
  uint32_t encoded = ((instruction >> 29) & 0x3U)
		     | ((instruction >> 3) & 0x1ffffcU);
  intptr_t delta = encoded;
  if (encoded & 0x100000U)
    delta -= 0x200000;
  return delta;
}

static uintptr_t
decode_adrp_page (uint32_t instruction, uintptr_t address)
{
  return (address & ~(uintptr_t) 0xfff)
	 + decode_page_delta (instruction) * 0x1000;
}

static unsigned int
decode_load_store_scale (uint32_t instruction)
{
  return aarch64_load_store_scale (instruction);
}

static uintptr_t
decode_pair_address (const aarch64_pseudo_reloc_result &result,
		     uintptr_t page_address)
{
  uintptr_t page = decode_adrp_page (result.page_instruction, page_address);
  uint32_t encoded_offset
    = (result.page_offset_instruction >> 10) & 0xfffU;

  if (aarch64_page_offset_kind (result.page_offset_instruction)
      == AARCH64_PSEUDO_RELOC_LOAD_STORE)
    encoded_offset <<= decode_load_store_scale (
			result.page_offset_instruction);
  return page + encoded_offset;
}

static int
check_observed_records ()
{
  static const struct
  {
    uint32_t page;
    uint32_t offset;
    uintptr_t page_address;
    uintptr_t import_slot;
    uint32_t expected_page;
    uint32_t expected_offset;
  } cases[] = {
    {
      0x90000001U, 0x912de021U,
      UINT64_C (0x1004017b8), UINT64_C (0x1004072d8),
      0xd0000021U, 0xf9416c21U
    },
    {
      0x90000000U, 0x912da000U,
      UINT64_C (0x100401910), UINT64_C (0x1004072c8),
      0xd0000020U, 0xf9416400U
    }
  };

  for (const auto &test : cases)
    {
      aarch64_pseudo_reloc_result result;
      if (aarch64_relocate_pseudo_pair (
	    &result, test.page, test.offset, test.page_address,
	    test.import_slot, UINT64_C (0x526841234))
	  != AARCH64_PSEUDO_RELOC_OK)
	return 1;
      if (result.kind != AARCH64_PSEUDO_RELOC_ADD
	  || result.page_instruction != test.expected_page
	  || result.page_offset_instruction != test.expected_offset
	  || decode_pair_address (result, test.page_address)
	     != test.import_slot)
	{
	  fprintf (stderr,
		   "observed result %08x/%08x address %llx, expected "
		   "%08x/%08x address %llx\n",
		   result.page_instruction, result.page_offset_instruction,
		   (unsigned long long) decode_pair_address (
					      result, test.page_address),
		   test.expected_page, test.expected_offset,
		   (unsigned long long) test.import_slot);
	  return 2;
	}
    }
  return 0;
}

static int
check_add_carry_and_range ()
{
  aarch64_pseudo_reloc_result result;
  uintptr_t page_address = UINT64_C (0x200001ffc);
  uintptr_t imported = UINT64_C (0x2000fffff);

  if (aarch64_relocate_pseudo_pair (
	&result, linked_adrp (1, 3), linked_add (3, 3),
	page_address, UINT64_C (0x200008000), imported)
      != AARCH64_PSEUDO_RELOC_OK)
    return 1;
  if (decode_pair_address (result, page_address) != imported + 1)
    return 2;

  imported = UINT64_C (0x200100000);
  if (aarch64_relocate_pseudo_pair (
	&result, linked_adrp (-1, 3), linked_add (3, 3),
	page_address, UINT64_C (0x200008000), imported)
      != AARCH64_PSEUDO_RELOC_OK)
    return 3;
  if (decode_pair_address (result, page_address) != imported - 1)
    return 4;

  if (aarch64_relocate_pseudo_pair (
	&result, linked_adrp (1, 3), linked_add (3, 3),
	UINT64_C (0x1000), UINT64_C (0x8000),
	UINT64_C (0x100001000))
      != AARCH64_PSEUDO_RELOC_OUT_OF_RANGE)
    return 5;

  if (aarch64_relocate_pseudo_pair (
	&result, linked_adrp (-1, 3), linked_add (3, 3),
	UINT64_C (0x100001000), UINT64_C (0x100008000),
	UINT64_C (0x1000))
      != AARCH64_PSEUDO_RELOC_OUT_OF_RANGE)
    return 6;

  if (aarch64_relocate_pseudo_pair (
	&result, linked_adrp (1, 3), linked_add (3, 3),
	UINT64_C (0x200000000), UINT64_C (0x200008000),
	UINT64_C (0x2ffffefff))
      != AARCH64_PSEUDO_RELOC_OK)
    return 7;

  if (aarch64_relocate_pseudo_pair (
	&result, linked_adrp (1, 3), linked_add (3, 3),
	UINT64_C (0x300000000), UINT64_C (0x300008000),
	UINT64_C (0x1ffffffff))
      != AARCH64_PSEUDO_RELOC_OK)
    return 8;

  if (aarch64_relocate_pseudo_pair (
	&result, linked_adrp (1, 3), linked_add (3, 3),
	UINT64_C (0x1000), UINT64_C (0x8000), UINTPTR_MAX)
      != AARCH64_PSEUDO_RELOC_ADDRESS_OVERFLOW)
    return 9;

  if (aarch64_relocate_pseudo_pair (
	&result, linked_adrp (-1, 3), linked_add (3, 3),
	UINT64_C (0x1000), UINT64_C (0x8000), 0)
      != AARCH64_PSEUDO_RELOC_ADDRESS_OVERFLOW)
    return 10;

  return 0;
}

static int
check_scaled_load_store ()
{
  static const uint32_t instructions[] = {
    0x39400020U, /* ldrb w0, [x1] */
    0x79400020U, /* ldrh w0, [x1] */
    0xb9400020U, /* ldr w0, [x1] */
    0xf9400020U, /* ldr x0, [x1] */
    0x3dc00020U, /* ldr q0, [x1] */
    0x39000020U, /* strb w0, [x1] */
    0x79000020U, /* strh w0, [x1] */
    0xb9000020U, /* str w0, [x1] */
    0xf9000020U, /* str x0, [x1] */
    0x3d800020U  /* str q0, [x1] */
  };

  for (uint32_t instruction : instructions)
    {
      unsigned int scale = decode_load_store_scale (instruction);
      uintptr_t imported = UINT64_C (0x300080000)
			   + ((uintptr_t) 0x9a0 & ~(((uintptr_t) 1 << scale)
						     - 1));
      aarch64_pseudo_reloc_result result;
      if (aarch64_relocate_pseudo_pair (
	    &result, linked_adrp (0, 1), instruction,
	    UINT64_C (0x300001000), UINT64_C (0x300006000), imported)
	  != AARCH64_PSEUDO_RELOC_OK)
	return 1;
      if (result.kind != AARCH64_PSEUDO_RELOC_LOAD_STORE
	  || decode_pair_address (result, UINT64_C (0x300001000))
	     != imported)
	return 2;

      if (scale != 0
	  && aarch64_relocate_pseudo_pair (
	       &result, linked_adrp (0, 1), instruction,
	       UINT64_C (0x300001000), UINT64_C (0x300006000),
	       imported + 1)
	     != AARCH64_PSEUDO_RELOC_MISALIGNED_PAGE_OFFSET)
	return 3;
    }

  aarch64_pseudo_reloc_result result;
  if (aarch64_relocate_pseudo_pair (
	&result, linked_adrp (0, 1), UINT32_C (0xf9400020),
	UINT64_C (0x1000), UINT64_C (0x8000),
	UINT64_C (0x100001000))
      != AARCH64_PSEUDO_RELOC_OUT_OF_RANGE)
    return 4;
  return 0;
}

static int
check_invalid_instructions ()
{
  aarch64_pseudo_reloc_result result;
  if (aarch64_relocate_pseudo_pair (
	&result, 0, linked_add (0, 1), 0x1000, 0x8000, 0x9000)
      != AARCH64_PSEUDO_RELOC_INVALID_PAGE_INSTRUCTION)
    return 1;
  if (aarch64_relocate_pseudo_pair (
	&result, linked_adrp (0, 1), 0, 0x1000, 0x8000, 0x9000)
      != AARCH64_PSEUDO_RELOC_INVALID_PAGE_OFFSET_INSTRUCTION)
    return 2;
  if (aarch64_relocate_pseudo_pair (
	&result, linked_adrp (0, 1), linked_add (0, 2),
	0x1000, 0x8000, 0x9000)
      != AARCH64_PSEUDO_RELOC_REGISTER_MISMATCH)
    return 3;
  if (aarch64_relocate_pseudo_pair (
	&result, linked_adrp (0, 31), linked_add (0, 31),
	0x1000, 0x8000, 0x9000)
      != AARCH64_PSEUDO_RELOC_REGISTER_MISMATCH)
    return 4;
  if (aarch64_relocate_pseudo_pair (
	&result, linked_adrp (0, 1), linked_add (1, 1),
	0x1000, 0x8004, UINT64_C (0x700000000))
      != AARCH64_PSEUDO_RELOC_MISALIGNED_PAGE_OFFSET)
    return 5;
  if (aarch64_relocate_pseudo_pair (
	&result, linked_adrp (0, 1), linked_add (2, 1),
	0x1000, 0x8000, UINT64_C (0x700000000))
      != AARCH64_PSEUDO_RELOC_REGISTER_MISMATCH)
    return 6;
  if (aarch64_relocate_pseudo_pair (
	&result, linked_adrp (0, 1), linked_add (1, 1),
	0x1000, UINT64_C (0x100001000), UINT64_C (0x700000000))
      != AARCH64_PSEUDO_RELOC_OUT_OF_RANGE)
    return 7;
  static const uint32_t invalid_offsets[] = {
    UINT32_C (0x11000021), /* 32-bit ADD */
    UINT32_C (0xb1000021), /* ADDS */
    UINT32_C (0x91400021), /* shifted ADD */
    UINT32_C (0xf9c00020)  /* reserved unsigned-immediate load/store */
  };
  for (uint32_t instruction : invalid_offsets)
    if (aarch64_relocate_pseudo_pair (
	  &result, linked_adrp (0, 1), instruction,
	  0x1000, 0x8000, UINT64_C (0x700000000))
	!= AARCH64_PSEUDO_RELOC_INVALID_PAGE_OFFSET_INSTRUCTION)
      return 8;
  if (aarch64_relocate_pseudo_pair (
	&result, UINT32_C (0x10000001), linked_add (1, 1),
	0x1000, 0x8000, UINT64_C (0x700000000))
      != AARCH64_PSEUDO_RELOC_INVALID_PAGE_INSTRUCTION)
    return 9;
  return 0;
}

static int
check_encoding_boundaries ()
{
  uint32_t instruction = UINT32_C (0x90000000);
  if (aarch64_encode_adrp (
	&instruction, UINT64_C (0x100000000), 0)
      != AARCH64_PSEUDO_RELOC_OK
      || instruction != UINT32_C (0x90800000))
    return 1;

  instruction = UINT32_C (0x90000000);
  if (aarch64_encode_adrp (
	&instruction, UINT64_C (0x100000000),
	UINT64_C (0x1fffff000))
      != AARCH64_PSEUDO_RELOC_OK
      || instruction != UINT32_C (0xf07fffe0))
    return 2;

  instruction = UINT32_C (0x90000000);
  if (aarch64_encode_adrp (
	&instruction, UINT64_C (0x100000000),
	UINT64_C (0x200000000))
      != AARCH64_PSEUDO_RELOC_OUT_OF_RANGE)
    return 3;

  instruction = UINT32_C (0x90000000);
  if (aarch64_encode_adrp (
	&instruction, UINT64_C (0x100001000), 0)
      != AARCH64_PSEUDO_RELOC_OUT_OF_RANGE)
    return 4;

  static const struct
  {
    uint32_t instruction;
    uint32_t offset;
  } load_store_cases[] = {
    { UINT32_C (0x393ff000), 0xffc },
    { UINT32_C (0x791ff800), 0xffc },
    { UINT32_C (0xb90ffc00), 0xffc },
    { UINT32_C (0xf907fc00), 0xff8 },
    { UINT32_C (0x3d83fc00), 0xff0 }
  };

  for (const auto &test : load_store_cases)
    {
      aarch64_pseudo_reloc_result result;
      if (aarch64_relocate_pseudo_pair (
	    &result, UINT32_C (0x90000000), test.instruction,
	    UINT64_C (0x100000), UINT64_C (0x200000),
	    UINT64_C (0x100000) + test.offset)
	  != AARCH64_PSEUDO_RELOC_OK
	  || result.page_instruction != UINT32_C (0x90000000)
	  || result.page_offset_instruction != test.instruction)
	return 5;
    }
  return 0;
}

static uint64_t random_state = UINT64_C (0x6a09e667f3bcc909);

static uint64_t
next_random ()
{
  random_state ^= random_state << 13;
  random_state ^= random_state >> 7;
  random_state ^= random_state << 17;
  return random_state;
}

static int
check_randomized_pairs ()
{
  for (unsigned int i = 0; i < 100000; ++i)
    {
      uintptr_t page_address
	= UINT64_C (0x400000000)
	  + ((next_random () & 0xfffffU) << 12)
	  + (next_random () & 0xffcU);
      unsigned int reg = (next_random () % 30) + 1;
      aarch64_pseudo_reloc_result result;

      if ((i % 3) == 0)
	{
	  intptr_t slot_pages = (intptr_t) (next_random () & 0x7ffffU)
				- 0x40000;
	  uintptr_t import_slot
	    = ((page_address & ~(uintptr_t) 0xfff)
	       + slot_pages * 0x1000)
	      | ((next_random () & 0x1ffU) << 3);
	  uintptr_t imported = UINT64_C (0x700000000000)
			       + (next_random () & 0xfffffff8U);
	  if (aarch64_relocate_pseudo_pair (
		&result, linked_adrp (0, reg),
		linked_add (reg, reg), page_address,
		import_slot, imported)
	      != AARCH64_PSEUDO_RELOC_OK
	      || decode_pair_address (result, page_address) != import_slot
	      || result.kind != AARCH64_PSEUDO_RELOC_ADD)
	    return 1;
	}
      else
	{
	  intptr_t addend = (intptr_t) (next_random () & 0x1fffffU)
			    - 0x100000;
	  if (addend == 0)
	    addend = 1;
	  intptr_t target_pages = (intptr_t) (next_random () & 0x7ffffU)
				  - 0x40000;
	  uintptr_t imported
	    = ((page_address & ~(uintptr_t) 0xfff)
	       + target_pages * 0x1000)
	      | (next_random () & 0xfffU);
	  uintptr_t expected;
	  if (aarch64_add_import_addend (imported, addend, &expected)
	      != AARCH64_PSEUDO_RELOC_OK)
	    return 2;
	  if (aarch64_relocate_pseudo_pair (
		&result, linked_adrp (addend, reg),
		linked_add (reg, reg), page_address,
		(page_address & ~(uintptr_t) 0xfff) + 0x8000,
		imported)
	      != AARCH64_PSEUDO_RELOC_OK
	      || decode_pair_address (result, page_address) != expected)
	    return 3;
	}
    }
  return 0;
}

static int
write_observed (const char *path, bool after)
{
  FILE *output = fopen (path, "wb");
  if (!output)
    return 1;

  static const struct
  {
    uint32_t page;
    uint32_t offset;
    uintptr_t page_address;
    uintptr_t import_slot;
  } cases[] = {
    {
      0x90000001U, 0x912de021U,
      UINT64_C (0x1004017b8), UINT64_C (0x1004072d8)
    },
    {
      0x90000000U, 0x912da000U,
      UINT64_C (0x100401910), UINT64_C (0x1004072c8)
    }
  };

  for (const auto &test : cases)
    {
      uint32_t page = test.page;
      uint32_t offset = test.offset;
      if (after)
	{
	  aarch64_pseudo_reloc_result result;
	  if (aarch64_relocate_pseudo_pair (
		&result, page, offset, test.page_address, test.import_slot,
		UINT64_C (0x526841234))
	      != AARCH64_PSEUDO_RELOC_OK)
	    {
	      fclose (output);
	      return 2;
	    }
	  page = result.page_instruction;
	  offset = result.page_offset_instruction;
	}
      if (fwrite (&page, sizeof page, 1, output) != 1
	  || fwrite (&offset, sizeof offset, 1, output) != 1)
	{
	  fclose (output);
	  return 3;
	}
    }
  return fclose (output) == 0 ? 0 : 4;
}

int
main (int argc, char **argv)
{
  if (argc == 3 && strcmp (argv[1], "--write-observed-before") == 0)
    return write_observed (argv[2], false);
  if (argc == 3 && strcmp (argv[1], "--write-observed-after") == 0)
    return write_observed (argv[2], true);
  if (argc != 1)
    return 64;

  int status = check_observed_records ();
  if (status != 0)
    {
      fprintf (stderr, "observed record check failed: %d\n", status);
      return 1;
    }
  status = check_add_carry_and_range ();
  if (status != 0)
    {
      fprintf (stderr, "carry/range check failed: %d\n", status);
      return 2;
    }
  status = check_scaled_load_store ();
  if (status != 0)
    {
      fprintf (stderr, "scaled load/store check failed: %d\n", status);
      return 3;
    }
  status = check_invalid_instructions ();
  if (status != 0)
    {
      fprintf (stderr, "invalid instruction check failed: %d\n", status);
      return 4;
    }
  status = check_randomized_pairs ();
  if (status != 0)
    {
      fprintf (stderr, "randomized pair check failed: %d\n", status);
      return 5;
    }
  status = check_encoding_boundaries ();
  if (status != 0)
    {
      fprintf (stderr, "encoding boundary check failed: %d\n", status);
      return 6;
    }
  return 0;
}
