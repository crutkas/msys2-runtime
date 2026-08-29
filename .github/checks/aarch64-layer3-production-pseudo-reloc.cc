#include "../../winsup/cygwin/pseudo-reloc.cc"

extern "C" DWORD
layer3_apply_production_reloc (DWORD opcode, DWORD flags, DWORD sym,
			       DWORD target)
{
  struct
  {
    runtime_pseudo_reloc_v2 header;
    runtime_pseudo_reloc_item_v2 item;
  } records = { { 0, 0, RP_VERSION_V2 }, { sym, target, flags } };
  static unsigned char image[4 * 4096] __attribute__ ((aligned (4096)));

  memset (image, 0, sizeof image);
  *(ptrdiff_t *) (image + sym) = (ptrdiff_t) image;
  *(DWORD *) (image + target) = opcode;
  do_pseudo_reloc (&records, (&records) + 1, image);
  return *(DWORD *) (image + target);
}
