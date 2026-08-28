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
   chain and Y is not replayed at dlclose time.

   The runtime is identified by volume and file index against the just-built
   winsup/testsuite/testinst/bin/msys-2.0.dll supplied by the caller, never by
   module base name alone, so a same-named image reached through PATH, a
   preload, a junction or a copy cannot satisfy the binding.  */

#include <windows.h>
#include <stdlib.h>
#include <string.h>

/* Registration modes.  winsup.api/dll_unload.c mirrors these values. */
#define DLL_UNLOAD_MODE_FULL 0u
#define DLL_UNLOAD_MODE_OMIT_EXPORTED 1u

/* Base name of the runtime image under test.  Only used to obtain the module
   handle; identity is then proven by file index, not by this name.  */
#define DLL_UNLOAD_RUNTIME_NAME "msys-2.0.dll"

typedef int (*atexit_export_fn) (void (*) (void));

struct file_identity
{
  DWORD volume;
  DWORD index_high;
  DWORD index_low;
};

static char log_path[MAX_PATH];
static char loaded_runtime_path[MAX_PATH];
static struct file_identity loaded_runtime_identity;
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

/* Canonicalise through an open handle rather than through the textual path,
   so the comparison is on stable volume and file index rather than on any
   spelling of the name.  */
static int
query_identity (const char *win32_path, struct file_identity *out)
{
  BY_HANDLE_FILE_INFORMATION info;
  BOOL ok;
  HANDLE file;

  if (!win32_path || !*win32_path)
    return 0;
  file = CreateFileA (win32_path, 0,
		      FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
		      NULL, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, NULL);
  if (file == INVALID_HANDLE_VALUE)
    return 0;
  memset (&info, 0, sizeof (info));
  ok = GetFileInformationByHandle (file, &info);
  CloseHandle (file);
  if (!ok)
    return 0;
  out->volume = info.dwVolumeSerialNumber;
  out->index_high = info.nFileIndexHigh;
  out->index_low = info.nFileIndexLow;
  return 1;
}

static int
same_file (const struct file_identity *a, const struct file_identity *b)
{
  return a->volume == b->volume && a->index_high == b->index_high
	 && a->index_low == b->index_low;
}

/* Resolve the runtime's exported atexit.  Every step is checked, the loaded
   image is proven to be the expected file, and the result is proven to live
   inside that image rather than being the statically linked shim that
   libmsys-2.0.a contributes to this DLL.  */
static int
resolve_runtime_atexit (const char *expected_win32_path,
			atexit_export_fn *out)
{
  struct file_identity expected;
  MEMORY_BASIC_INFORMATION info;
  HMODULE runtime;
  FARPROC entry;
  DWORD length;

  if (!expected_win32_path || !*expected_win32_path)
    return 1;
  if (!query_identity (expected_win32_path, &expected))
    return 2;

  runtime = GetModuleHandleA (DLL_UNLOAD_RUNTIME_NAME);
  if (!runtime)
    return 3;
  length = GetModuleFileNameA (runtime, loaded_runtime_path,
			       sizeof (loaded_runtime_path));
  if (length == 0 || length >= sizeof (loaded_runtime_path))
    return 4;
  if (!query_identity (loaded_runtime_path, &loaded_runtime_identity))
    return 5;
  if (!same_file (&expected, &loaded_runtime_identity))
    return 6;

  entry = GetProcAddress (runtime, "atexit");
  if (!entry)
    return 7;
  memset (&info, 0, sizeof (info));
  if (VirtualQuery ((const void *) entry, &info, sizeof (info))
      != sizeof (info))
    return 8;
  if (info.AllocationBase != (void *) runtime)
    return 9;
  if ((void *) entry == (void *) &atexit)
    return 10;

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
     11..20  runtime resolution failed (see resolve_runtime_atexit)  */
__attribute__ ((dllexport)) int
dll_unload_register (const char *path, unsigned mode,
		     void (*exe_callback) (void),
		     const char *expected_runtime_win32_path)
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

  status = resolve_runtime_atexit (expected_runtime_win32_path, &entry);
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

__attribute__ ((dllexport)) const char *
dll_unload_loaded_runtime_path (void)
{
  return loaded_runtime_path;
}

__attribute__ ((dllexport)) int
dll_unload_runtime_identity (unsigned long *volume, unsigned long *high,
			     unsigned long *low)
{
  if (!volume || !high || !low)
    return 1;
  *volume = (unsigned long) loaded_runtime_identity.volume;
  *high = (unsigned long) loaded_runtime_identity.index_high;
  *low = (unsigned long) loaded_runtime_identity.index_low;
  return 0;
}

/* Negative-control entry point: report whether a candidate path names the
   very file this DLL bound to.  Returns 0 for the bound runtime, 1 when the
   candidate is a different file, and 2 when it cannot be identified.  */
__attribute__ ((dllexport)) int
dll_unload_path_is_bound_runtime (const char *win32_path)
{
  struct file_identity candidate;

  if (!query_identity (win32_path, &candidate))
    return 2;
  return same_file (&candidate, &loaded_runtime_identity) ? 0 : 1;
}
