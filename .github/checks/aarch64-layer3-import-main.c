__declspec(dllimport) int layer3_import_add (int);
__declspec(dllimport) extern int layer3_import_data;
__declspec(dllimport) void ExitProcess (unsigned long);

void
mainCRTStartup (void)
{
  ExitProcess (layer3_import_data == 37 && layer3_import_add (5) == 42
	       ? 0 : 1);
}

void *layer3_import_reloc_anchor = (void *) mainCRTStartup;
