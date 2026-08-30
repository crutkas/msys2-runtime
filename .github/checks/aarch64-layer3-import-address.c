#include <stdint.h>

extern int layer3_import_add (int);
__declspec(dllimport) void ExitProcess (unsigned long);
__declspec(dllimport) void *GetModuleHandleA (const char *);
__declspec(dllimport) void *GetProcAddress (void *, const char *);
void *layer3_production_import_address (void *);
void *layer3_reloc_anchor = &layer3_reloc_anchor;

void
mainCRTStartup (void)
{
  uint32_t malformed[3] = { 0x90000010, 0xf9400210, 0xd61f0220 };
  void *module = GetModuleHandleA ("layer3_import.dll");
  void *expected = GetProcAddress (module, "layer3_import_add_v2");
  void *decoded
    = layer3_production_import_address ((void *) layer3_import_add);

  if (!module)
    ExitProcess (2);
  if (!expected)
    ExitProcess (3);
  if (!decoded)
    ExitProcess (4);
  if (decoded != expected)
    ExitProcess (5);
  if (layer3_production_import_address (malformed) != 0)
    ExitProcess (6);
  ExitProcess (0);
}
