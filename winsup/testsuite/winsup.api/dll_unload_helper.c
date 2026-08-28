/* Cygwin-aware helper DLL for unload/finalizer lifecycle testing.

   Markers appended to the shared log, in the order they are produced:

     R  registration completed inside this DLL
     T  the exported touch entry point was reached
     A  callback registered through the statically linked atexit shim
	(winsup/cygwin/lib/atexit.c, pulled in from libmsys-2.0.a)
     C  callback registered through __cxa_atexit directly
     X  callback registered through the msys-2.0.dll exported atexit, with
	the callback body resident in this DLL
     Y  callback registered through the msys-2.0.dll exported atexit, with
	the callback body resident in the calling executable
     D  DLL destructor

   The statically linked atexit shim resolves __dso_handle at compile time and
   never reaches cygwin_atexit, so it does not exercise the runtime's module
   inference at all.  X and Y are registered through the runtime's exported
   atexit, which is cygwin_atexit (see winsup/cygwin/cygwin.din), and which
   infers the owning module from _my_tls.retaddr ().

   Only Y discriminates that inference.  cygwin_atexit falls back to
   dlls.find (fn) when the return-address lookup fails, and that fallback can
   silently rescue X because the X callback lives in this DLL.  It can never
   rescue Y, whose callback lives in the executable: if the return-address
   lookup fails for Y, cygwin_atexit degrades to the process-global atexit
   chain and Y is not replayed at dlclose time.  */

#include <windows.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

/* Registration modes.  winsup.api/dll_unload.c mirrors these values. */
#define DLL_UNLOAD_MODE_FULL 0u
#define DLL_UNLOAD_MODE_OMIT_EXPORTED 1u

/* Name of the runtime image under test. */
#define DLL_UNLOAD_RUNTIME_NAME "msys-2.0.dll"

typedef int (*atexit_export_fn) (void (*) (void));

static char log_path[MAX_PATH];
static atexit_export_fn resolved_exported_atexit;
static void *resolved_static_atexit;

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
  (void) unused;
  append_marker ('C');
}

static void
exported_dll_callback (void)
{
  append_marker ('X');
}

static void __attribute__ ((destructor))
helper_destructor (void)
{
  append_marker ('D');
}

/* Resolve the runtime's exported atexit.  Every step is checked, and the
   result is proven to live inside the runtime image rather than being the
   statically linked shim that libmsys-2.0.a contributes to this DLL.  */
static int
resolve_runtime_atexit (atexit_export_fn *out)
{
  HMODULE runtime = GetModuleHandleA (DLL_UNLOAD_RUNTIME_NAME);
  if (!runtime)
    return 1;

  char module_path[MAX_PATH];
  DWORD length = GetModuleFileNameA (runtime, module_path,
				     sizeof (module_path));
  if (length == 0 || length >= sizeof (module_path))
    return 2;

  const char *base = module_path;
  for (const char *p = module_path; *p; ++p)
    if (*p == '\\' || *p == '/')
      base = p + 1;
  if (strcasecmp (base, DLL_UNLOAD_RUNTIME_NAME) != 0)
    return 3;

  FARPROC entry = GetProcAddress (runtime, "atexit");
  if (!entry)
    return 4;

  MEMORY_BASIC_INFORMATION info;
  memset (&info, 0, sizeof (info));
  if (VirtualQuery ((const void *) entry, &info, sizeof (info))
      != sizeof (info))
    return 5;
  if (info.AllocationBase != (void *) runtime)
    return 6;
  if ((void *) entry == (void *) &atexit)
    return 7;

  *out = (atexit_export_fn) (void *) entry;
  return 0;
}

/* Call the runtime export from a real, non-inlined, non-tail call frame that
   belongs to this DLL.  cygwin_atexit reads the return address the SIGFE stub
   recorded, so the call context must stay inside this image; the volatile
   result and the barrier keep GCC from turning this into a sibling call, the
   exact optimization that winsup/cygwin/dcrt0.cc warns about.  */
static int __attribute__ ((noinline, noclone))
register_from_this_dll (atexit_export_fn entry, void (*callback) (void))
{
  volatile int result;

  result = entry (callback);
  __asm__ __volatile__ ("" : : : "memory");
  return (int) result;
}

/* Register the unload callbacks.

   Returns 0 on success, or:
      1  invalid log path
      2  statically linked atexit shim refused the registration
      3  __cxa_atexit refused the registration
      4  no executable-resident callback supplied for a full registration
      5  the runtime export refused the DLL-resident callback
      6  the runtime export refused the executable-resident callback
      7  unknown mode
      8  the log could not be marked
     11..17  runtime atexit resolution failed (see resolve_runtime_atexit)  */
__attribute__ ((dllexport)) int
dll_unload_register (const char *path, unsigned mode,
		     void (*exe_callback) (void))
{
  extern int __cxa_atexit (void (*) (void *), void *, void *);
  extern void *__dso_handle;
  atexit_export_fn entry = NULL;
  int status;
  size_t length;

  if (!path)
    return 1;
  length = strlen (path);
  if (length == 0 || length >= sizeof (log_path))
    return 1;
  memcpy (log_path, path, length + 1);

  if (mode != DLL_UNLOAD_MODE_FULL && mode != DLL_UNLOAD_MODE_OMIT_EXPORTED)
    return 7;

  status = resolve_runtime_atexit (&entry);
  if (status != 0)
    return 10 + status;
  resolved_exported_atexit = entry;
  resolved_static_atexit = (void *) &atexit;

  /* Registration order is A, C, X, Y.  dll_list::detach runs
     __cxa_finalize first, which replays the chain last-in first-out, and
     only then runs the DLL destructors.  The observable unload order is
     therefore Y, X, C, A, D.  */
  if (atexit (atexit_callback) != 0)
    return 2;
  if (__cxa_atexit (cxa_callback, NULL, &__dso_handle) != 0)
    return 3;

  if (mode == DLL_UNLOAD_MODE_FULL)
    {
      if (!exe_callback)
	return 4;
      if (register_from_this_dll (entry, exported_dll_callback) != 0)
	return 5;
      if (register_from_this_dll (entry, exe_callback) != 0)
	return 6;
    }

  return append_marker ('R') ? 0 : 8;
}

__attribute__ ((dllexport)) int
dll_unload_touch (void)
{
  return append_marker ('T') ? 0 : 1;
}

/* Report the resolved runtime export so the executable can prove that the
   registration really went through msys-2.0.dll and not through the shim. */
__attribute__ ((dllexport)) void *
dll_unload_exported_atexit (void)
{
  return (void *) resolved_exported_atexit;
}

__attribute__ ((dllexport)) void *
dll_unload_static_atexit (void)
{
  return resolved_static_atexit;
}
