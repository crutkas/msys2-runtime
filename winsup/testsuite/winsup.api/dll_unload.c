/* Verify Cygwin-aware DLL finalizers and list teardown across reloads.

   The helper DLL registers unload callbacks through four distinct
   mechanisms and this program checks the exact marker sequence the runtime
   replays.  See winsup.api/dll_unload_helper.c for the marker vocabulary.

   Two negative controls run inside the same test so that a passing result
   cannot be vacuous:

     * an omitted-registration variant, which proves the positive marker
       expectation is falsifiable rather than trivially satisfied, and
     * a mis-associated registration, made through the very same runtime
       export but from executable code, which must never be replayed when
       the helper DLL is unloaded.  */

#include <windows.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <unistd.h>
#include <sys/stat.h>

/* Registration modes.  winsup.api/dll_unload_helper.c mirrors these. */
#define DLL_UNLOAD_MODE_FULL 0u
#define DLL_UNLOAD_MODE_OMIT_EXPORTED 1u

#define DLL_UNLOAD_RUNTIME_NAME "msys-2.0.dll"
#define DLL_UNLOAD_HELPER_LEAF "/dll_unload_helper.dll"

/* Registration order inside the helper is A, C, X, Y.  dll_list::detach
   replays the __cxa chain last-in first-out and only afterwards runs the DLL
   destructors, so a full load produces R T Y X C A D.  Omitting the runtime
   export registrations removes exactly Y and X.  */
static const char expected_full[] = "RTYXCAD";
static const char expected_omit[] = "RTCAD";

typedef int (*register_fn) (const char *, unsigned, void (*) (void));
typedef int (*touch_fn) (void);
typedef void *(*addr_fn) (void);
typedef int (*atexit_export_fn) (void (*) (void));

static char helper_log_path[MAX_PATH];
static atexit_export_fn exe_runtime_atexit;
static volatile int misassociated_runs;

static int
append_marker (char marker)
{
  HANDLE file = CreateFileA (helper_log_path, FILE_APPEND_DATA,
			     FILE_SHARE_READ | FILE_SHARE_WRITE, NULL,
			     OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
  if (file == INVALID_HANDLE_VALUE)
    return 0;

  DWORD written = 0;
  BOOL ok = WriteFile (file, &marker, 1, &written, NULL);
  CloseHandle (file);
  return ok && written == 1;
}

/* Resident in this executable on purpose: the helper registers it through
   the runtime export, so cygwin_atexit's dlls.find (fn) fallback cannot
   associate it with the helper DLL.  Seeing 'Y' at unload time therefore
   proves the _my_tls.retaddr () module inference itself worked.  */
static void
exe_unload_callback (void)
{
  append_marker ('Y');
}

/* Negative control.  Registered through the same runtime export but from
   executable code, so neither dlls.find (retaddr) nor dlls.find (fn) can
   reach the helper DLL and the callback must stay on the process-global
   chain instead of being replayed by dlclose.  */
static void
misassociated_callback (void)
{
  misassociated_runs = 1;
}

static int __attribute__ ((noinline, noclone))
register_from_this_executable (atexit_export_fn entry,
			       void (*callback) (void))
{
  volatile int result;

  result = entry (callback);
  __asm__ __volatile__ ("" : : : "memory");
  return (int) result;
}

/* Resolve the runtime's exported atexit with every step checked.  Mirrors
   the helper's resolution so the two results can be compared.  */
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

/* Compose the helper path from the directory of the running executable so
   the test does not depend on the current working directory.  */
static int
derive_helper_path (char *out, size_t size)
{
  char exe_path[MAX_PATH];
  ssize_t length = readlink ("/proc/self/exe", exe_path,
			     sizeof (exe_path) - 1);
  if (length <= 0 || (size_t) length >= sizeof (exe_path))
    return 1;
  exe_path[length] = '\0';

  size_t directory = 0;
  for (size_t i = 0; i < (size_t) length; ++i)
    if (exe_path[i] == '/' || exe_path[i] == '\\')
      directory = i;
  if (directory == 0)
    return 2;

  if (directory + sizeof (DLL_UNLOAD_HELPER_LEAF) > size)
    return 3;
  memcpy (out, exe_path, directory);
  memcpy (out + directory, DLL_UNLOAD_HELPER_LEAF,
	  sizeof (DLL_UNLOAD_HELPER_LEAF));

  struct stat helper;
  if (stat (out, &helper) != 0 || !S_ISREG (helper.st_mode))
    return 4;
  return 0;
}

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
matches_repeated (const char *actual, size_t length, const char *unit,
		  size_t repeats)
{
  size_t unit_length = strlen (unit);

  if (length != unit_length * repeats)
    return 0;
  for (size_t i = 0; i < length; ++i)
    if (actual[i] != unit[i % unit_length])
      return 0;
  return 1;
}

static int
load_once (const char *helper_path, unsigned mode)
{
  void *module = dlopen (helper_path, RTLD_NOW);
  if (!module)
    {
      fprintf (stderr, "dlopen %s failed: %s\n", helper_path, dlerror ());
      return 1;
    }

  register_fn register_callbacks
    = (register_fn) dlsym (module, "dll_unload_register");
  touch_fn touch = (touch_fn) dlsym (module, "dll_unload_touch");
  addr_fn exported_addr
    = (addr_fn) dlsym (module, "dll_unload_exported_atexit");
  addr_fn static_addr = (addr_fn) dlsym (module, "dll_unload_static_atexit");
  if (!register_callbacks || !touch || !exported_addr || !static_addr)
    {
      fprintf (stderr, "dlsym failed: %s\n", dlerror ());
      dlclose (module);
      return 2;
    }

  int status = register_callbacks (helper_log_path, mode, exe_unload_callback);
  if (status != 0)
    {
      fprintf (stderr, "helper callback registration failed: %d\n", status);
      dlclose (module);
      return 3;
    }

  void *dll_exported = exported_addr ();
  void *dll_static = static_addr ();
  if (!dll_exported)
    {
      fprintf (stderr, "helper did not resolve the runtime atexit export\n");
      dlclose (module);
      return 4;
    }
  if (dll_exported == dll_static)
    {
      fprintf (stderr,
	       "helper resolved the statically linked atexit shim at %p\n",
	       dll_exported);
      dlclose (module);
      return 5;
    }
  if (dll_exported != (void *) exe_runtime_atexit)
    {
      fprintf (stderr,
	       "helper export %p does not match executable export %p\n",
	       dll_exported, (void *) exe_runtime_atexit);
      dlclose (module);
      return 6;
    }

  if (register_from_this_executable (exe_runtime_atexit,
				     misassociated_callback) != 0)
    {
      fprintf (stderr, "mis-associated control registration failed\n");
      dlclose (module);
      return 7;
    }

  if (touch () != 0)
    {
      fprintf (stderr, "helper touch failed\n");
      dlclose (module);
      return 8;
    }
  if (dlclose (module) != 0)
    {
      fprintf (stderr, "dlclose failed: %s\n", dlerror ());
      return 9;
    }
  return 0;
}

int
main (void)
{
  char helper_path[MAX_PATH];
  char temp_directory[MAX_PATH];
  char positive_log[MAX_PATH];
  char negative_log[MAX_PATH];
  char actual[64];
  int status;

  status = derive_helper_path (helper_path, sizeof (helper_path));
  if (status)
    {
      fprintf (stderr, "helper path derivation failed: %d\n", status);
      return 1;
    }

  status = resolve_runtime_atexit (&exe_runtime_atexit);
  if (status)
    {
      fprintf (stderr, "runtime atexit export resolution failed: %d\n",
	       status);
      return 2;
    }

  if (!GetTempPathA (sizeof (temp_directory), temp_directory)
      || !GetTempFileNameA (temp_directory, "dlu", 0, positive_log)
      || !GetTempFileNameA (temp_directory, "dln", 0, negative_log))
    {
      fprintf (stderr, "failed to create lifecycle logs: %lu\n",
	       GetLastError ());
      return 3;
    }

  int result = 0;

  memcpy (helper_log_path, positive_log, strlen (positive_log) + 1);
  for (int iteration = 0; iteration < 2; ++iteration)
    {
      status = load_once (helper_path, DLL_UNLOAD_MODE_FULL);
      if (status)
	{
	  result = 10 + status;
	  break;
	}

      int length = read_log (positive_log, actual, sizeof (actual));
      if (length < 0
	  || !matches_repeated (actual, (size_t) length, expected_full,
				(size_t) iteration + 1))
	{
	  fprintf (stderr,
		   "unload lifecycle mismatch after iteration %d: "
		   "expected %d repeats of \"%s\", observed \"%s\"\n",
		   iteration + 1, iteration + 1, expected_full,
		   length >= 0 ? actual : "<read failure>");
	  result = 30 + iteration;
	  break;
	}

      if (misassociated_runs != 0)
	{
	  fprintf (stderr,
		   "mis-associated callback ran during unload %d\n",
		   iteration + 1);
	  result = 40 + iteration;
	  break;
	}
    }

  /* Negative control: with the runtime-export registrations omitted the
     sequence must be exactly the reduced one and must not satisfy the
     positive expectation.  */
  if (result == 0)
    {
      memcpy (helper_log_path, negative_log, strlen (negative_log) + 1);
      status = load_once (helper_path, DLL_UNLOAD_MODE_OMIT_EXPORTED);
      if (status)
	result = 50 + status;
      else
	{
	  int length = read_log (negative_log, actual, sizeof (actual));
	  if (length < 0)
	    {
	      fprintf (stderr, "omitted-registration control log unreadable\n");
	      result = 70;
	    }
	  /* The verifier used by the positive phase must reject this real
	     execution, otherwise the positive assertion is vacuous.  */
	  else if (matches_repeated (actual, (size_t) length, expected_full, 1))
	    {
	      fprintf (stderr,
		       "omitted-registration control satisfied the positive "
		       "expectation \"%s\"\n", expected_full);
	      result = 71;
	    }
	  else if (!matches_repeated (actual, (size_t) length, expected_omit, 1))
	    {
	      fprintf (stderr,
		       "omitted-registration control mismatch: expected "
		       "\"%s\", observed \"%s\"\n", expected_omit, actual);
	      result = 72;
	    }
	  else if (misassociated_runs != 0)
	    {
	      fprintf (stderr,
		       "mis-associated callback ran during the control "
		       "unload\n");
	      result = 73;
	    }
	}
    }

  DeleteFileA (positive_log);
  DeleteFileA (negative_log);
  return result;
}
