/* Cygwin-aware helper DLL for unload/finalizer lifecycle testing. */

#include <windows.h>
#include <stdlib.h>
#include <string.h>

static char log_path[MAX_PATH];

static int
append_marker (char marker)
{
  HANDLE file = CreateFileA (log_path, FILE_APPEND_DATA,
			     FILE_SHARE_READ | FILE_SHARE_WRITE, NULL,
			     OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
  if (file == INVALID_HANDLE_VALUE)
    return 0;

  DWORD written = 0;
  BOOL ok = WriteFile (file, &marker, 1, &written, NULL);
  CloseHandle (file);
  return ok && written == 1;
}

static void
atexit_callback (void)
{
  append_marker ('A');
}

static void
cxa_callback (void *unused)
{
  append_marker ('C');
}

static void __attribute__ ((destructor))
helper_destructor (void)
{
  append_marker ('D');
}

__attribute__ ((dllexport)) int
dll_unload_register (const char *path)
{
  size_t length = strlen (path);
  if (length == 0 || length >= sizeof (log_path))
    return 1;
  memcpy (log_path, path, length + 1);

  extern int __cxa_atexit (void (*) (void *), void *, void *);
  extern void *__dso_handle;
  if (atexit (atexit_callback) != 0)
    return 2;
  if (__cxa_atexit (cxa_callback, NULL, &__dso_handle) != 0)
    return 3;
  return append_marker ('R') ? 0 : 4;
}

__attribute__ ((dllexport)) int
dll_unload_touch (void)
{
  return append_marker ('T') ? 0 : 1;
}
