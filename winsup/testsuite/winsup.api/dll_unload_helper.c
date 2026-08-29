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

   The runtime is identified by canonical final path, volume and file index
   against the just-built winsup/testsuite/testinst/bin/msys-2.0.dll supplied
   by the caller, never by module base name alone.  Handles remain open without
   delete sharing through callback registration and unload, preventing the
   compared files from being renamed or replaced during the tested cycle.  */

#include <windows.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

/* Registration modes.  winsup.api/dll_unload.c mirrors these values. */
#define DLL_UNLOAD_MODE_FULL 0u
#define DLL_UNLOAD_MODE_OMIT_EXPORTED 1u

/* Base name of the runtime image under test.  Only used to obtain the module
   handle; identity is then proven by file index, not by this name.  */
#define DLL_UNLOAD_RUNTIME_NAME "msys-2.0.dll"

typedef int (*atexit_export_fn) (void (*) (void));
typedef DWORD (WINAPI *final_path_fn) (HANDLE, LPSTR, DWORD, DWORD);

/* Resolved at runtime because the testsuite does not select a Windows
   version new enough for the w32api header to expose this entry point. */
static final_path_fn
resolve_final_path (void)
{
  static final_path_fn cached;

  if (!cached)
    {
      HMODULE kernel = GetModuleHandleA ("kernel32.dll");
      if (kernel)
	cached = (final_path_fn) (void *)
	  GetProcAddress (kernel, "GetFinalPathNameByHandleA");
    }
  return cached;
}

struct file_identity
{
  HANDLE handle;
  DWORD volume;
  DWORD index_high;
  DWORD index_low;
  char final_path[MAX_PATH];
};

static char log_path[MAX_PATH];
static char loaded_runtime_path[MAX_PATH];
static struct file_identity expected_runtime_identity;
static struct file_identity loaded_runtime_identity;
static atexit_export_fn resolved_exported_atexit;
static void *resolved_static_atexit;

static void close_identity (struct file_identity *);

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
  close_identity (&loaded_runtime_identity);
  close_identity (&expected_runtime_identity);
}

/* Canonicalise through an open handle rather than through the textual path,
   so the comparison is on the normalised final path plus the stable volume
   and file index rather than on any spelling of the name.  */
static int
query_identity (const char *win32_path, struct file_identity *out)
{
  BY_HANDLE_FILE_INFORMATION info;
  final_path_fn final_path = resolve_final_path ();
  DWORD final;
  BOOL ok;
  HANDLE file;

  memset (out, 0, sizeof (*out));
  out->handle = INVALID_HANDLE_VALUE;
  if (!win32_path || !*win32_path || !final_path)
    return 0;
  file = CreateFileA (win32_path, 0,
		      FILE_SHARE_READ | FILE_SHARE_WRITE,
		      NULL, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, NULL);
  if (file == INVALID_HANDLE_VALUE)
    return 0;
  memset (&info, 0, sizeof (info));
  memset (out->final_path, 0, sizeof (out->final_path));
  ok = GetFileInformationByHandle (file, &info);
  final = final_path (file, out->final_path, sizeof (out->final_path), 0);
  if (!ok || final == 0 || final >= sizeof (out->final_path))
    {
      CloseHandle (file);
      return 0;
    }
  out->handle = file;
  out->volume = info.dwVolumeSerialNumber;
  out->index_high = info.nFileIndexHigh;
  out->index_low = info.nFileIndexLow;
  return 1;
}

static void
close_identity (struct file_identity *identity)
{
  if (identity->handle && identity->handle != INVALID_HANDLE_VALUE)
    CloseHandle (identity->handle);
  identity->handle = INVALID_HANDLE_VALUE;
}

static int
identity_open (const struct file_identity *identity)
{
  return identity->handle && identity->handle != INVALID_HANDLE_VALUE;
}

static int
same_file (const struct file_identity *a, const struct file_identity *b)
{
  return a->volume == b->volume && a->index_high == b->index_high
	 && a->index_low == b->index_low
	 && strcasecmp (a->final_path, b->final_path) == 0;
}

/* Resolve the runtime's exported atexit.  Every step is checked, the loaded
   image is proven to be the expected file, and the result is proven to live
   inside that image rather than being the statically linked shim that
   libmsys-2.0.a contributes to this DLL.  */
static int
resolve_runtime_atexit (const char *expected_win32_path,
			atexit_export_fn *out)
{
  MEMORY_BASIC_INFORMATION info;
  HMODULE runtime;
  FARPROC entry;
  DWORD length;

  if (!expected_win32_path || !*expected_win32_path)
    return 1;
  if (!query_identity (expected_win32_path, &expected_runtime_identity))
    return 2;

  runtime = GetModuleHandleA (DLL_UNLOAD_RUNTIME_NAME);
  if (!runtime)
    {
      close_identity (&expected_runtime_identity);
      return 3;
    }
  length = GetModuleFileNameA (runtime, loaded_runtime_path,
			       sizeof (loaded_runtime_path));
  if (length == 0 || length >= sizeof (loaded_runtime_path))
    {
      close_identity (&expected_runtime_identity);
      return 4;
    }
  if (!query_identity (loaded_runtime_path, &loaded_runtime_identity))
    {
      close_identity (&expected_runtime_identity);
      return 5;
    }
  if (!same_file (&expected_runtime_identity, &loaded_runtime_identity))
    {
      close_identity (&loaded_runtime_identity);
      close_identity (&expected_runtime_identity);
      return 6;
    }

  entry = GetProcAddress (runtime, "atexit");
  if (!entry)
    {
      close_identity (&loaded_runtime_identity);
      close_identity (&expected_runtime_identity);
      return 7;
    }
  memset (&info, 0, sizeof (info));
  if (VirtualQuery ((const void *) entry, &info, sizeof (info))
      != sizeof (info))
    {
      close_identity (&loaded_runtime_identity);
      close_identity (&expected_runtime_identity);
      return 8;
    }
  if (info.AllocationBase != (void *) runtime)
    {
      close_identity (&loaded_runtime_identity);
      close_identity (&expected_runtime_identity);
      return 9;
    }
  if ((void *) entry == (void *) &atexit)
    {
      close_identity (&loaded_runtime_identity);
      close_identity (&expected_runtime_identity);
      return 10;
    }

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

__attribute__ ((dllexport)) const char *
dll_unload_loaded_runtime_final_path (void)
{
  return loaded_runtime_identity.final_path;
}

__attribute__ ((dllexport)) int
dll_unload_runtime_identity (unsigned long *volume, unsigned long *high,
			     unsigned long *low, int *expected_open,
			     int *loaded_open)
{
  if (!volume || !high || !low || !expected_open || !loaded_open)
    return 1;
  if (!identity_open (&expected_runtime_identity)
      || !identity_open (&loaded_runtime_identity))
    return 2;
  *volume = (unsigned long) loaded_runtime_identity.volume;
  *high = (unsigned long) loaded_runtime_identity.index_high;
  *low = (unsigned long) loaded_runtime_identity.index_low;
  *expected_open = 1;
  *loaded_open = 1;
  return 0;
}

/* Negative-control entry point: report whether a candidate path names the
   very file this DLL bound to.  Returns 0 for the bound runtime, 1 when the
   candidate is a different file, and 2 when it cannot be identified.  */
__attribute__ ((dllexport)) int
dll_unload_path_is_bound_runtime (const char *win32_path)
{
  struct file_identity candidate;
  int result;

  if (!query_identity (win32_path, &candidate))
    return 2;
  result = same_file (&candidate, &loaded_runtime_identity) ? 0 : 1;
  close_identity (&candidate);
  return result;
}
