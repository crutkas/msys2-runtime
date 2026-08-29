#include <stdint.h>

__declspec(dllimport) void ExitProcess (unsigned long);

struct pseudo_reloc_item
{
  uint32_t sym;
  uint32_t target;
  uint32_t flags;
};

__attribute__ ((section (".rdata_runtime_pseudo_reloc"), used))
static const struct
{
  uint32_t magic1;
  uint32_t magic2;
  uint32_t version;
  struct pseudo_reloc_item items[2];
} layer3_pseudo_reloc_shape = {
  0, 0, 1,
  {
    { 0x120, 0x220, 12 },
    { 0x3000, 0x1400, 21 }
  }
};

static int
apply_aarch64_pseudo_reloc (unsigned int width, uintptr_t base,
			    uintptr_t sym, uintptr_t target, uint32_t *opcode)
{
  uint32_t value = *opcode;
  uintptr_t relocation;

  switch (width)
    {
    case 12:
      value = 0xf9400000 | (value & 0x3ff);
      relocation = (base + sym) & ((1 << 12) - 1);
      value |= (uint32_t) ((relocation >> 3) << 10);
      break;
    case 21:
      value &= 0x9f00001f;
      relocation = ((base + sym) >> 12) - ((base + target) >> 12);
      relocation &= (1 << 21) - 1;
      value |= (uint32_t) ((relocation & 3) << 29);
      value |= (uint32_t) ((relocation >> 2) << 5);
      break;
    default:
      return 0;
    }

  *opcode = value;
  return 1;
}

struct import_thunk
{
  uint32_t opcodes[3];
  uint32_t padding;
  uintptr_t slot;
};

__attribute__ ((aligned (4096)))
static unsigned char thunk_pages[3 * 4096];

static uint32_t
encode_adrp (int pages)
{
  uint32_t immediate = (uint32_t) pages & ((1U << 21) - 1);
  return 0x90000010 | ((immediate & 3) << 29) | ((immediate >> 2) << 5);
}

static void
prepare_thunk (struct import_thunk *thunk, int pages, uintptr_t *slot,
	       uintptr_t expected)
{
  uintptr_t offset = (uintptr_t) slot & 0xfff;
  thunk->opcodes[0] = encode_adrp (pages);
  thunk->opcodes[1] = 0xf9400210 | (uint32_t) ((offset >> 3) << 10);
  thunk->opcodes[2] = 0xd61f0200;
  *slot = expected;
}

static void *
decode_import_address (const uint32_t *code)
{
  uint32_t opcode1 = code[0];
  uint32_t opcode2 = code[1];
  uint32_t opcode3 = code[2];

  if (((opcode1 & 0x9f00001f) == 0x90000010)
      && ((opcode2 & 0xffc003ff) == 0xf9400210)
      && opcode3 == 0xd61f0200)
    {
      uint32_t immhi = (opcode1 >> 5) & 0x7ffff;
      uint32_t immlo = (opcode1 >> 29) & 0x3;
      uint32_t imm12 = ((opcode2 >> 10) & 0xfff) * 8;
      int64_t pages = (immhi << 2) | immlo;
      if (pages & (1 << 20))
	pages -= 1 << 21;
      int64_t immediate = pages * 4096;
      intptr_t page = (intptr_t) code & ~(intptr_t) 0xfff;
      uintptr_t *slot = (uintptr_t *) (page + immediate + imm12);
      return (void *) *slot;
    }
  return 0;
}

uint32_t layer3_apply_production_reloc (uint32_t, uint32_t, uint32_t,
					uint32_t);

void
mainCRTStartup (void)
{
  uint32_t add_opcode = 0x91000010;
  uint32_t adrp_opcode = 0x90000010;
  uint32_t malformed_opcode = 0x14000000;
  uint32_t unchanged = malformed_opcode;
  uint32_t expected_12 = add_opcode;
  uint32_t expected_negative_21 = adrp_opcode;
  uint32_t expected_positive_21 = adrp_opcode;
  uintptr_t expected = (uintptr_t) mainCRTStartup;
  struct import_thunk *negative
    = (struct import_thunk *) (thunk_pages + 4096);
  struct import_thunk *positive
    = (struct import_thunk *) (thunk_pages + 4096 + 32);
  struct import_thunk *zero
    = (struct import_thunk *) (thunk_pages + 4096 + 64);
  uintptr_t *negative_slot = (uintptr_t *) (thunk_pages + 16);
  uintptr_t *positive_slot = (uintptr_t *) (thunk_pages + 8192 + 16);
  uintptr_t *zero_slot = (uintptr_t *) (thunk_pages + 4096 + 256);

  prepare_thunk (negative, -1, negative_slot, expected);
  prepare_thunk (positive, 1, positive_slot, expected);
  prepare_thunk (zero, 0, zero_slot, expected);
  apply_aarch64_pseudo_reloc (12, 0, 0x2018, 0x1000, &expected_12);
  apply_aarch64_pseudo_reloc (21, 0, 0x0000, 0x1000,
			      &expected_negative_21);
  apply_aarch64_pseudo_reloc (21, 0, 0x2000, 0x1000,
			      &expected_positive_21);

  if (layer3_apply_production_reloc (add_opcode, 12, 0x2018, 0x1000)
      != expected_12)
    ExitProcess (12);
  if (layer3_apply_production_reloc (adrp_opcode, 21, 0x0000, 0x1000)
      != expected_negative_21)
    ExitProcess (21);
  if (layer3_apply_production_reloc (adrp_opcode, 21, 0x2000, 0x1000)
      != expected_positive_21)
    ExitProcess (22);

  if (layer3_pseudo_reloc_shape.items[0].flags != 12
      || layer3_pseudo_reloc_shape.items[1].flags != 21
      || !apply_aarch64_pseudo_reloc (12, 0x100000, 0x128, 0x200,
				     &add_opcode)
      || (add_opcode & 0xffc00000) != 0xf9400000
      || !apply_aarch64_pseudo_reloc (21, 0x100000, 0x5000, 0x1000,
				     &adrp_opcode)
      || (adrp_opcode & 0x9f00001f) != 0x90000010
      || apply_aarch64_pseudo_reloc (26, 0x100000, 0, 0,
				    &malformed_opcode)
      || malformed_opcode != unchanged
      || decode_import_address (negative->opcodes) != (void *) expected
      || decode_import_address (positive->opcodes) != (void *) expected
      || decode_import_address (zero->opcodes) != (void *) expected)
    ExitProcess (1);

  negative->opcodes[2] = 0xd61f0220;
  ExitProcess (decode_import_address (negative->opcodes) == 0 ? 0 : 2);
}

void *layer3_pseudo_reloc_anchor = (void *) mainCRTStartup;
