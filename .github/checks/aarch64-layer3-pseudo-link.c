extern int layer3_import_data;
__declspec(dllimport) void ExitProcess (unsigned long);

void _pei386_runtime_relocator (void);

void
mainCRTStartup (void)
{
  _pei386_runtime_relocator ();
  ExitProcess (layer3_import_data == 37 ? 0 : 1);
}

void *layer3_pseudo_link_reloc_anchor = (void *) mainCRTStartup;
