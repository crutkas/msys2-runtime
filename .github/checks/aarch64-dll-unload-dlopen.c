#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

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
close_preserves_frame (void *module)
{
  uintptr_t fp_before;
  uintptr_t fp_after;
  uintptr_t sp_before;
  uintptr_t sp_after;

  __asm__ volatile ("mov %0, x29" : "=r" (fp_before));
  __asm__ volatile ("mov %0, sp" : "=r" (sp_before));
  if (dlclose (module) != 0)
    return 0;
  __asm__ volatile ("mov %0, sp" : "=r" (sp_after));
  __asm__ volatile ("mov %0, x29" : "=r" (fp_after));
  return sp_before == sp_after && fp_before == fp_after;
}

static int
register_probe (void *module, unsigned int id)
{
  unload_probe_register_fn probe_register;
  unload_probe_value_fn value;

  clear_events (id);
  probe_register = (unload_probe_register_fn)
    dlsym (module, "unload_probe_register");
  value = (unload_probe_value_fn) dlsym (module, "unload_probe_value");
  return (probe_register && value
	  && probe_register (record_event) == 42
	  && value () == 42);
}

static int
run_probe (const char *path, unsigned int id, int flags)
{
  void *module = dlopen (path, flags | RTLD_LOCAL);

  if (!module || !register_probe (module, id))
    return 0;
  if (!close_preserves_frame (module))
    return 0;
  return events_complete (id);
}

static int
run_multiple (int flags)
{
  void *one = dlopen ("./aarch64-dll-unload-probe-one.dll",
		      flags | RTLD_LOCAL);
  void *two = dlopen ("./aarch64-dll-unload-probe-two.dll",
		      flags | RTLD_LOCAL);

  if (!one || !two || !register_probe (one, 1) || !register_probe (two, 2))
    return 0;
  if (!close_preserves_frame (two) || !close_preserves_frame (one))
    return 0;
  return events_complete (1) && events_complete (2);
}

int
main (int argc, char **argv)
{
  int cycle;
  int flags;

  setvbuf (stdout, NULL, _IONBF, 0);
  setvbuf (stderr, NULL, _IONBF, 0);
  if (argc != 2)
    return 2;
  if (strcmp (argv[1], "now") == 0)
    flags = RTLD_NOW;
  else if (strcmp (argv[1], "lazy") == 0)
    flags = RTLD_LAZY;
  else
    return 3;

  printf ("dlopen-%s-start\n", argv[1]);
  for (cycle = 0; cycle < 3; ++cycle)
    if (!run_probe ("./aarch64-dll-unload-probe-one.dll", 1, flags))
      return 4;
  puts ("dlopen-repeated-unload-pass");
  if (!run_multiple (flags))
    return 5;
  puts ("dlopen-multiple-unload-pass");
  printf ("dlopen-%s-pass\n", argv[1]);
  return 0;
}
