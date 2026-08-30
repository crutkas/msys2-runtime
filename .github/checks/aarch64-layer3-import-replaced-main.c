int layer3_import_add (int);
__declspec(dllimport) void ExitProcess (unsigned long);

void
mainCRTStartup (void)
{
  ExitProcess (layer3_import_add (5) == 43 ? 0 : 1);
}

void *layer3_replaced_reloc_anchor = (void *) mainCRTStartup;
