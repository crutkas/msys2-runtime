/* Verify Cygwin-aware DLL finalizers and list teardown across reloads. */

#include <windows.h>
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>

typedef int (*register_fn) (const char *);
typedef int (*touch_fn) (void);

static int
read_log (const char *path, char *buffer, size_t size)
{
  HANDLE file = CreateFileA (path, GENERIC_READ,
			     FILE_SHARE_READ | FILE_SHARE_WRITE, NULL,
			     OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
  if (file == INVALID_HANDLE_VALUE)
    return -1;

  DWORD read = 0;
  BOOL ok = ReadFile (file, buffer, size - 1, &read, NULL);
  CloseHandle (file);
  if (!ok || read >= size)
    return -1;
  buffer[read] = '\0';
  return (int) read;
}

static int
load_once (const char *log_path)
{
  void *module = dlopen ("./winsup.api/dll_unload_helper.dll", RTLD_NOW);
  if (!module)
    {
      fprintf (stderr, "dlopen failed: %s\n", dlerror ());
      return 1;
    }

  register_fn register_callbacks
    = (register_fn) dlsym (module, "dll_unload_register");
  touch_fn touch = (touch_fn) dlsym (module, "dll_unload_touch");
  if (!register_callbacks || !touch)
    {
      fprintf (stderr, "dlsym failed: %s\n", dlerror ());
      dlclose (module);
      return 2;
    }
  if (register_callbacks (log_path) != 0 || touch () != 0)
    {
      fprintf (stderr, "helper callback registration failed\n");
      dlclose (module);
      return 3;
    }
  if (dlclose (module) != 0)
    {
      fprintf (stderr, "dlclose failed: %s\n", dlerror ());
      return 4;
    }
  return 0;
}

int
main (void)
{
  char temp_path[MAX_PATH];
  char log_path[MAX_PATH];
  if (!GetTempPathA (sizeof (temp_path), temp_path)
      || !GetTempFileNameA (temp_path, "dlu", 0, log_path))
    {
      fprintf (stderr, "failed to create lifecycle log: %lu\n",
	       GetLastError ());
      return 1;
    }

  static const char expected[] = "RTCADRTCAD";
  char actual[sizeof (expected) + 8];
  for (int iteration = 0; iteration < 2; ++iteration)
    {
      int status = load_once (log_path);
      if (status)
	{
	  DeleteFileA (log_path);
	  return 10 + status;
	}

      int length = read_log (log_path, actual, sizeof (actual));
      size_t expected_length = (iteration + 1) * 5;
      if (length != (int) expected_length
	  || memcmp (actual, expected, expected_length) != 0)
	{
	  fprintf (stderr,
		   "unload lifecycle mismatch after iteration %d: \"%s\"\n",
		   iteration + 1, length >= 0 ? actual : "<read failure>");
	  DeleteFileA (log_path);
	  return 20 + iteration;
	}
    }

  DeleteFileA (log_path);
  return 0;
}
