#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>
#include <windows.h>
#include <tlhelp32.h>

typedef int (*callback_fn) (void);

enum
{
  UNLOAD_EVENT_COUNT = 6
};

static const char *const event_names[UNLOAD_EVENT_COUNT] = {
  "process-attach",
  "constructor",
  "callback",
  "process-detach",
  "destructor",
  "atexit"
};

static int
verify_events (int expected)
{
  FILE *file;
  char line[80];
  int counts[UNLOAD_EVENT_COUNT] = { 0 };
  int index;

  file = fopen ("aarch64-dll-unload-events.txt", "r");
  if (!file)
    return expected == 0 ? 0 : 30;

  while (fgets (line, sizeof line, file))
    {
      line[strcspn (line, "\r\n")] = '\0';
      for (index = 0; index < UNLOAD_EVENT_COUNT; ++index)
	if (strcmp (line, event_names[index]) == 0)
	  break;
      if (index == UNLOAD_EVENT_COUNT)
	{
	  fclose (file);
	  return 31;
	}
      ++counts[index];
    }
  fclose (file);

  for (index = 0; index < UNLOAD_EVENT_COUNT; ++index)
    if (counts[index] != expected)
      {
	fprintf (stderr, "%s: expected %d, observed %d\n",
		 event_names[index], expected, counts[index]);
	return 32 + index;
      }
  return 0;
}

static int
module_base_name (const wchar_t *path, const wchar_t **base)
{
  const wchar_t *backslash = wcsrchr (path, L'\\');
  const wchar_t *slash = wcsrchr (path, L'/');

  if (!backslash || (slash && slash > backslash))
    backslash = slash;
  if (backslash)
    *base = backslash + 1;
  else
    *base = path;
  return **base != L'\0';
}

static HMODULE
module_handle (const wchar_t *path)
{
  const wchar_t *base;

  if (!module_base_name (path, &base))
    return NULL;
  return GetModuleHandleW (base);
}

static int
module_snapshot_count (const wchar_t *path)
{
  MODULEENTRY32W entry = { 0 };
  HANDLE snapshot;
  const wchar_t *base;
  int count = 0;

  if (!module_base_name (path, &base))
    return -1;
  entry.dwSize = sizeof entry;
  snapshot = CreateToolhelp32Snapshot (TH32CS_SNAPMODULE
				      | TH32CS_SNAPMODULE32,
				      GetCurrentProcessId ());
  if (snapshot == INVALID_HANDLE_VALUE)
    return -1;
  if (Module32FirstW (snapshot, &entry))
    do
      {
	if (lstrcmpiW (entry.szModule, base) == 0)
	  ++count;
      }
    while (Module32NextW (snapshot, &entry));
  else if (GetLastError () != ERROR_NO_MORE_FILES)
    {
      CloseHandle (snapshot);
      return -1;
    }
  CloseHandle (snapshot);
  return count;
}

static int
module_is_unloaded (const wchar_t *path, int cycle)
{
  HMODULE handle;
  int snapshot_count;
  const wchar_t *base;

  if (!module_base_name (path, &base))
    return 0;
  handle = module_handle (path);
  snapshot_count = module_snapshot_count (path);
  printf ("cycle=%d module=%ls api_handle=%p snapshot_count=%d\n",
	  cycle, base, (void *) handle, snapshot_count);
  return handle == NULL && snapshot_count == 0;
}

struct native_thread_case
{
  const wchar_t *path;
  HMODULE loaded;
  HMODULE after;
  int loaded_snapshot_count;
  int unloaded_snapshot_count;
};

static DWORD WINAPI
native_thread_main (LPVOID parameter)
{
  struct native_thread_case *test = (struct native_thread_case *) parameter;
  FARPROC address;
  callback_fn callback;

  test->loaded = LoadLibraryExW (test->path, NULL, 0);
  if (!test->loaded)
    return 40;
  test->loaded_snapshot_count = module_snapshot_count (test->path);
  address = GetProcAddress (test->loaded, "aarch64_dll_unload_callback");
  __builtin_memcpy (&callback, &address, sizeof callback);
  if (!callback || callback () != 42)
    return 41;
  if (!FreeLibrary (test->loaded))
    return 42;
  test->after = module_handle (test->path);
  test->unloaded_snapshot_count = module_snapshot_count (test->path);
  if (test->after != NULL || test->unloaded_snapshot_count != 0)
    return 43;
  return 0;
}

static int
run_native_threads (const wchar_t *path, int cycles)
{
  int cycle;

  for (cycle = 0; cycle < cycles; ++cycle)
    {
      struct native_thread_case test = { path, NULL, NULL, -1, -1 };
      DWORD status;
      HANDLE thread = CreateThread (NULL, 0, native_thread_main, &test, 0, NULL);

      if (!thread)
	return 44;
      if (WaitForSingleObject (thread, INFINITE) != WAIT_OBJECT_0
	  || !GetExitCodeThread (thread, &status))
	{
	  CloseHandle (thread);
	  return 45;
	}
      CloseHandle (thread);
      printf ("cycle=%d raw-win32-thread loaded=%p loaded_snapshot_count=%d"
	      " api_handle=%p unloaded_snapshot_count=%d status=%lu\n",
	      cycle + 1, (void *) test.loaded, test.loaded_snapshot_count,
	      (void *) test.after, test.unloaded_snapshot_count,
	      (unsigned long) status);
      if (status != 0 || test.loaded_snapshot_count < 1)
	return status ? (int) status : 46;
    }
  return 0;
}

static int
run_loadlibrary (const wchar_t *path, int cycles, DWORD flags,
		 int call_export)
{
  int cycle;

  for (cycle = 0; cycle < cycles; ++cycle)
    {
      HMODULE module = LoadLibraryExW (path, NULL, flags);
      int snapshot_count;

      if (!module)
	return 10;
      snapshot_count = module_snapshot_count (path);
      printf ("cycle=%d loaded=%p snapshot_count=%d\n",
	      cycle + 1, (void *) module, snapshot_count);
      if (module_handle (path) != module || snapshot_count < 1)
	return 14;
      if (call_export)
	{
	  FARPROC address = GetProcAddress (module,
					    "aarch64_dll_unload_callback");
	  callback_fn callback;

	  memcpy (&callback, &address, sizeof callback);
	  if (!callback || callback () != 42)
	    return 11;
	}
      if (!FreeLibrary (module))
	return 12;
      if (!module_is_unloaded (path, cycle + 1))
	return 13;
    }
  return 0;
}

static int
run_dlopen (const char *path, const wchar_t *wide_path, int cycles, int flags)
{
  int cycle;

  for (cycle = 0; cycle < cycles; ++cycle)
    {
      void *module = dlopen (path, flags | RTLD_LOCAL);
      callback_fn callback;
      int snapshot_count;

      if (!module)
	return 20;
      snapshot_count = module_snapshot_count (wide_path);
      printf ("cycle=%d loaded=%p snapshot_count=%d\n",
	      cycle + 1, module, snapshot_count);
      if (module_handle (wide_path) == NULL || snapshot_count < 1)
	return 24;
      callback = (callback_fn) dlsym (module,
				      "aarch64_dll_unload_callback");
      if (!callback || callback () != 42)
	return 21;
      if (dlclose (module) != 0)
	return 22;
      if (!module_is_unloaded (wide_path, cycle + 1))
	return 23;
    }
  return 0;
}

int
main (int argc, char **argv)
{
  wchar_t path[MAX_PATH];
  char *end;
  long cycles;
  int expected;
  int result;

  if (argc != 4)
    return 2;
  cycles = strtol (argv[3], &end, 10);
  if (*end || cycles < 1 || cycles > 100)
    return 3;
  if (!DeleteFileA ("aarch64-dll-unload-events.txt")
      && GetLastError () != ERROR_FILE_NOT_FOUND)
    return 4;
  if (!MultiByteToWideChar (CP_UTF8, 0, argv[2], -1, path, MAX_PATH))
    return 5;

  if (strcmp (argv[1], "loadlibrary") == 0)
    {
      expected = cycles;
      result = run_loadlibrary (path, cycles, 0, 1);
    }
  else if (strcmp (argv[1], "dont-resolve") == 0)
    {
      expected = 0;
      result = run_loadlibrary (path, cycles,
				DONT_RESOLVE_DLL_REFERENCES, 0);
    }
  else if (strcmp (argv[1], "entry0") == 0)
    {
      expected = 0;
      result = run_loadlibrary (path, cycles, 0, 0);
    }
  else if (strcmp (argv[1], "native-thread") == 0)
    {
      expected = cycles;
      result = run_native_threads (path, cycles);
    }
  else if (strcmp (argv[1], "dlopen-now") == 0)
    {
      expected = cycles;
      result = run_dlopen (argv[2], path, cycles, RTLD_NOW);
    }
  else if (strcmp (argv[1], "dlopen-lazy") == 0)
    {
      expected = cycles;
      result = run_dlopen (argv[2], path, cycles, RTLD_LAZY);
    }
  else
    return 6;

  if (result)
    return result;
  result = verify_events (expected);
  if (result)
    return result;
  puts ("aarch64-dll-unload=pass");
  return 0;
}
