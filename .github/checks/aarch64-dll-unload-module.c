#include <stdlib.h>
#include <windows.h>

static const char events_file[] = "aarch64-dll-unload-events.txt";

static void
record_event (const char *event)
{
  HANDLE file;
  DWORD written;

  file = CreateFileA (events_file, FILE_APPEND_DATA, FILE_SHARE_READ, NULL,
		      OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
  if (file != INVALID_HANDLE_VALUE)
    {
      WriteFile (file, event, lstrlenA (event), &written, NULL);
      CloseHandle (file);
    }
}

static void
finalizer (void)
{
  record_event ("atexit\n");
}

static void __attribute__ ((constructor))
constructor (void)
{
  record_event ("constructor\n");
  if (atexit (finalizer) != 0)
    record_event ("atexit-register-failed\n");
}

static void __attribute__ ((destructor))
destructor (void)
{
  record_event ("destructor\n");
}

BOOL WINAPI
DllMain (HINSTANCE instance, DWORD reason, LPVOID reserved)
{
  (void) instance;
  (void) reserved;
  if (reason == DLL_PROCESS_ATTACH)
    record_event ("process-attach\n");
  else if (reason == DLL_PROCESS_DETACH)
    record_event ("process-detach\n");
  return TRUE;
}

__declspec (dllexport) int
aarch64_dll_unload_callback (void)
{
  record_event ("callback\n");
  return 42;
}
