#include <stdint.h>
#include <windows.h>

#include "aarch64-dll-unload-probe.h"

#if !defined(__aarch64__)
#error A native AArch64 compiler is required
#endif

static unsigned int event_counts[3][5];

static void
record_event (unsigned int module, unsigned int event)
{
  if (module < 3 && event < 5)
    ++event_counts[module][event];
}

static void
write_marker (const char *text, DWORD length)
{
  DWORD written;
  HANDLE output = GetStdHandle (STD_OUTPUT_HANDLE);

  if (output != INVALID_HANDLE_VALUE)
    WriteFile (output, text, length, &written, NULL);
}

#define MARKER(text) write_marker (text "\r\n", sizeof (text "\r\n") - 1)

static void
clear_events (unsigned int module)
{
  unsigned int event;

  for (event = 0; event < 5; ++event)
    event_counts[module][event] = 0;
}

static int
events_complete (unsigned int module)
{
  return (event_counts[module][UNLOAD_PROBE_READY] == 1
	  && event_counts[module][UNLOAD_PROBE_DLL_DETACH] == 1
	  && event_counts[module][UNLOAD_PROBE_ATEXIT] == 1
	  && event_counts[module][UNLOAD_PROBE_DTOR] == 1);
}

__attribute__ ((noinline))
static int
free_library_preserves_frame (HMODULE module)
{
  uintptr_t fp_before;
  uintptr_t fp_after;
  uintptr_t sp_before;
  uintptr_t sp_after;

  __asm__ volatile ("mov %0, x29" : "=r" (fp_before));
  __asm__ volatile ("mov %0, sp" : "=r" (sp_before));
  if (!FreeLibrary (module))
    return 0;
  __asm__ volatile ("mov %0, sp" : "=r" (sp_after));
  __asm__ volatile ("mov %0, x29" : "=r" (fp_after));
  return sp_before == sp_after && fp_before == fp_after;
}

static int
run_control (const wchar_t *path, DWORD flags)
{
  HMODULE module = LoadLibraryExW (path, NULL, flags);

  if (!module)
    return 0;
  return free_library_preserves_frame (module);
}

static int
run_minimal (const wchar_t *path)
{
  HMODULE module;
  unload_probe_value_fn value;

  module = LoadLibraryExW (path, NULL, 0);
  if (!module)
    return 0;
  value = (unload_probe_value_fn) GetProcAddress (module,
						 "unload_probe_value");
  if (!value || value () != 42)
    return 0;
  return free_library_preserves_frame (module);
}

static int
register_probe (HMODULE module, unsigned int id)
{
  unload_probe_register_fn probe_register;
  unload_probe_value_fn value;

  clear_events (id);
  probe_register = (unload_probe_register_fn)
    GetProcAddress (module, "unload_probe_register");
  value = (unload_probe_value_fn)
    GetProcAddress (module, "unload_probe_value");
  return (probe_register && value
	  && probe_register (record_event) == 42
	  && value () == 42);
}

static int
run_probe (const wchar_t *path, unsigned int id)
{
  HMODULE module = LoadLibraryExW (path, NULL, 0);

  if (!module || !register_probe (module, id))
    return 0;
  if (!free_library_preserves_frame (module))
    return 0;
  return events_complete (id);
}

static int
run_multiple (void)
{
  HMODULE one;
  HMODULE two;

  one = LoadLibraryExW (L"aarch64-dll-unload-probe-one.dll", NULL, 0);
  two = LoadLibraryExW (L"aarch64-dll-unload-probe-two.dll", NULL, 0);
  if (!one || !two || !register_probe (one, 1) || !register_probe (two, 2))
    return 0;
  if (!free_library_preserves_frame (two)
      || !free_library_preserves_frame (one))
    return 0;
  return events_complete (1) && events_complete (2);
}

void
mainCRTStartup (void)
{
  int cycle;
  int result = 0;

  MARKER ("native-unload-start");
  if (!run_control (L"aarch64-dll-unload-data.dll",
		    DONT_RESOLVE_DLL_REFERENCES)
      || !run_control (L"aarch64-dll-unload-data.dll", 0))
    result = 1;
  else
    MARKER ("entrypoint-zero-controls-pass");

  if (!result
      && !run_control (L"aarch64-dll-unload-probe-one.dll",
		       DONT_RESOLVE_DLL_REFERENCES))
    result = 2;
  else if (!result)
    MARKER ("dont-resolve-control-pass");

  if (!result && !run_minimal (L"aarch64-dll-unload-minimal.dll"))
    result = 3;
  else if (!result)
    MARKER ("native-no-tls-minimal-pass");

  for (cycle = 0; !result && cycle < 3; ++cycle)
    if (!run_probe (L"aarch64-dll-unload-probe-one.dll", 1))
      result = 4;
  if (!result)
    MARKER ("native-repeated-unload-pass");

  if (!result && !run_multiple ())
    result = 5;
  else if (!result)
    MARKER ("native-multiple-unload-pass");

  if (!result)
    MARKER ("native-unload-pass");
  ExitProcess (result);
}
