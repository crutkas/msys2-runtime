#include <stdlib.h>
#include <windows.h>

#include "aarch64-dll-unload-probe.h"

#if !defined(__aarch64__)
#error A native AArch64 compiler is required
#endif

#ifndef UNLOAD_PROBE_MODULE
#error UNLOAD_PROBE_MODULE must identify this DLL
#endif

enum
{
  STATE_CTOR = 1,
  STATE_ATEXIT_REGISTERED = 2,
  STATE_DLL_ATTACH = 4
};

static __thread unsigned int probe_tls = 0x641dU + UNLOAD_PROBE_MODULE;
static unload_probe_callback probe_callback;
static unsigned int probe_state;

static void
emit (enum unload_probe_event event)
{
  if (probe_callback)
    probe_callback (UNLOAD_PROBE_MODULE, event);
}

static void
probe_atexit (void)
{
  emit (UNLOAD_PROBE_ATEXIT);
}

__attribute__ ((constructor))
static void
probe_ctor (void)
{
  probe_state |= STATE_CTOR;
  if (atexit (probe_atexit) == 0)
    probe_state |= STATE_ATEXIT_REGISTERED;
}

__attribute__ ((destructor))
static void
probe_dtor (void)
{
  emit (UNLOAD_PROBE_DTOR);
}

BOOL APIENTRY
DllMain (HINSTANCE instance, DWORD reason, LPVOID reserved)
{
  (void) instance;
  (void) reserved;

  if (reason == DLL_PROCESS_ATTACH)
    probe_state |= STATE_DLL_ATTACH;
  else if (reason == DLL_PROCESS_DETACH)
    emit (UNLOAD_PROBE_DLL_DETACH);
  return TRUE;
}

__declspec (dllexport) int
unload_probe_register (unload_probe_callback callback)
{
  unsigned int expected = (STATE_CTOR
			   | STATE_ATEXIT_REGISTERED
			   | STATE_DLL_ATTACH);

  probe_callback = callback;
  emit (UNLOAD_PROBE_READY);
  if (probe_state != expected
      || probe_tls != 0x641dU + UNLOAD_PROBE_MODULE)
    return -1;
  return 42;
}

__declspec (dllexport) int
unload_probe_value (void)
{
  return probe_tls == 0x641dU + UNLOAD_PROBE_MODULE ? 42 : -1;
}
