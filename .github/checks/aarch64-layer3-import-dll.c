__declspec(dllexport) int layer3_import_data = 37;

__declspec(dllexport) int
layer3_import_add (int value)
{
  return value + layer3_import_data;
}

__declspec(dllexport) int
layer3_import_add_v2 (int value)
{
  return value + layer3_import_data + 1;
}

__declspec(dllexport) int
WSAStartup (unsigned short version, void *data)
{
  unsigned short *words = (unsigned short *) data;
  words[0] = version;
  words[1] = version;
  return 0;
}

int
DllMainCRTStartup (void *instance, unsigned long reason, void *reserved)
{
  return instance != 0 || reason == 0 || reserved == 0;
}

void *layer3_dll_reloc_anchor = (void *) layer3_import_add;
