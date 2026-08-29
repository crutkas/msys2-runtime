#include <stdint.h>

__declspec(dllimport) void ExitProcess (unsigned long);
__declspec(dllimport) unsigned long GetEnvironmentVariableA (
  const char *, char *, unsigned long);
__declspec(dllimport) unsigned long GetLastError (void);

long layer3_import_add (long);
long layer3_missing_optional (void);
long layer3_missing_fatal (void);
long layer3_absent_optional (void);
extern int32_t layer3_autoload_chain_calls;

void
api_fatal (const char *format, ...)
{
  (void) format;
  ExitProcess (91);
}

void
mainCRTStartup (void)
{
  char mode[16] = { 0 };
  GetEnvironmentVariableA ("LAYER3_AUTOLOAD_CASE", mode, sizeof mode);

  if (mode[0] == 'f')
    layer3_missing_fatal ();
  if (mode[0] == 'n')
    ExitProcess (layer3_missing_optional () == 73
		 && GetLastError () == 127 ? 0 : 2);
  if (mode[0] == 'l')
    ExitProcess (layer3_absent_optional () == 74
		 && GetLastError () == 127 ? 0 : 3);

  long first = layer3_import_add (5);
  long second = layer3_import_add (6);
  ExitProcess (first == 42 && second == 43
	       && layer3_autoload_chain_calls == 1 ? 0 : 1);
}
