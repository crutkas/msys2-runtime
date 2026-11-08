#ifndef AARCH64_DLL_UNLOAD_PROBE_H
#define AARCH64_DLL_UNLOAD_PROBE_H

enum unload_probe_event
{
  UNLOAD_PROBE_READY = 1,
  UNLOAD_PROBE_DLL_DETACH = 2,
  UNLOAD_PROBE_ATEXIT = 3,
  UNLOAD_PROBE_DTOR = 4
};

typedef void (*unload_probe_callback) (unsigned int, unsigned int);
typedef int (*unload_probe_register_fn) (unload_probe_callback);
typedef int (*unload_probe_value_fn) (void);

#endif
