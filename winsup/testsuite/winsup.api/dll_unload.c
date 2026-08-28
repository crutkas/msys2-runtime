/* Verify Cygwin-aware DLL finalizers and list teardown across reloads.

   The helper DLL registers unload callbacks through four distinct
   mechanisms and this program checks the exact marker sequence the runtime
   replays.  See winsup.api/dll_unload_helper.c for the marker vocabulary.

   Three negative controls run inside this test so that a passing result
   cannot be vacuous:

     * an omitted-registration variant, which proves the positive marker
       expectation is falsifiable rather than trivially satisfied,
     * a mis-associated registration, made through the very same runtime
       export but from executable code, which must never be replayed when
       the helper DLL is unloaded, and
     * a decoy file that shares the runtime base name, which must not
       satisfy the runtime identity binding.

   Every check emits a machine-readable DIAG record on success as well as on
   failure, so a passing run carries its own evidence.  */

#include <windows.h>
#include <dlfcn.h>
#include <sys/cygwin.h>
#include <sys/stat.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

/* Registration modes.  winsup.api/dll_unload_helper.c mirrors these. */
#define DLL_UNLOAD_MODE_FULL 0u
#define DLL_UNLOAD_MODE_OMIT_EXPORTED 1u

#define DLL_UNLOAD_RUNTIME_NAME "msys-2.0.dll"
#define DLL_UNLOAD_HELPER_LEAF "/dll_unload_helper.dll"
#define DLL_UNLOAD_RUNTIME_LEAF "/testinst/bin/" DLL_UNLOAD_RUNTIME_NAME

/* Registration order inside the helper is A, C, X, Y.  dll_list::detach
   replays the __cxa chain last-in first-out and only afterwards runs the DLL
   destructors, so a full load produces R T Y X C A D.  Omitting the runtime
   export registrations removes exactly Y and X.  */
static const char expected_full[] = "RTYXCAD";
static const char expected_omit[] = "RTCAD";

typedef int (*register_fn) (const char *, unsigned, void (*) (void),
			    const char *);
typedef int (*touch_fn) (void);
typedef void *(*addr_fn) (void);
typedef const char *(*path_fn) (void);
typedef int (*identity_fn) (unsigned long *, unsigned long *, unsigned long *);
typedef int (*bound_fn) (const char *);
typedef int (*atexit_export_fn) (void (*) (void));

struct file_identity
{
  DWORD volume;
  DWORD index_high;
  DWORD index_low;
};

static char helper_log_path[MAX_PATH];
static char runtime_win32_path[MAX_PATH];
static atexit_export_fn exe_runtime_atexit;
static volatile int misassociated_runs;
static int controls_passed;
static int runtime_records_emitted;

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

/* Record values may contain spaces; emit them as single parseable tokens. */
static void
print_token (const char *value)
{
  if (!value || !*value)
    {
      fputs ("-", stdout);
      return;
    }
  for (const char *p = value; *p; ++p)
    putchar ((*p == ' ' || *p == '\t' || *p == '"') ? '_' : *p);
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

/* Mirrors the helper resolution so the two results can be compared. */
static int
resolve_runtime_atexit (const char *expected_win32_path,
			atexit_export_fn *out)
{
  struct file_identity expected;
  struct file_identity loaded;
  MEMORY_BASIC_INFORMATION info;
  char module_path[MAX_PATH];
  HMODULE runtime;
  FARPROC entry;
  DWORD length;

  if (!query_identity (expected_win32_path, &expected))
    return 1;
  runtime = GetModuleHandleA (DLL_UNLOAD_RUNTIME_NAME);
  if (!runtime)
    return 2;
  length = GetModuleFileNameA (runtime, module_path, sizeof (module_path));
  if (length == 0 || length >= sizeof (module_path))
    return 3;
  if (!query_identity (module_path, &loaded))
    return 4;
  if (!same_file (&expected, &loaded))
    return 5;
  entry = GetProcAddress (runtime, "atexit");
  if (!entry)
    return 6;
  memset (&info, 0, sizeof (info));
  if (VirtualQuery ((const void *) entry, &info, sizeof (info))
      != sizeof (info))
    return 7;
  if (info.AllocationBase != (void *) runtime)
    return 8;
  if ((void *) entry == (void *) &atexit)
    return 9;
  *out = (atexit_export_fn) (void *) entry;
  return 0;
}

/* Locate the directory of the running executable, returning the offset of
   the separator that ends it.  */
static int
executable_directory (char *out, size_t size, size_t *directory,
		      size_t *parent)
{
  ssize_t length = readlink ("/proc/self/exe", out, size - 1);
  size_t seen = 0;

  if (length <= 0 || (size_t) length >= size)
    return 1;
  out[length] = '\0';

  for (size_t i = (size_t) length; i-- > 0; )
    if (out[i] == '/' || out[i] == '\\')
      {
	if (seen == 0)
	  {
	    *directory = i;
	    seen = 1;
	  }
	else
	  {
	    *parent = i;
	    seen = 2;
	    break;
	  }
      }
  if (seen != 2 || *directory == 0 || *parent == 0)
    return 2;
  return 0;
}

static int
derive_helper_path (char *out, size_t size)
{
  char exe_path[MAX_PATH];
  size_t directory = 0;
  size_t parent = 0;
  struct stat helper;
  int status = executable_directory (exe_path, sizeof (exe_path), &directory,
				     &parent);
  if (status)
    return status;

  if (directory + sizeof (DLL_UNLOAD_HELPER_LEAF) > size)
    return 3;
  memcpy (out, exe_path, directory);
  memcpy (out + directory, DLL_UNLOAD_HELPER_LEAF,
	  sizeof (DLL_UNLOAD_HELPER_LEAF));

  if (stat (out, &helper) != 0 || !S_ISREG (helper.st_mode))
    return 4;
  return 0;
}

/* The runtime under test is installed by winsup/cygwin/Makefile.am into
   <testsuite builddir>/testinst/bin, which is the parent directory of the
   directory holding this executable.  That layout is trusted harness state,
   so the expected path is derived from it rather than from PATH.  */
static int
derive_runtime_path (char *out, size_t size)
{
  char exe_path[MAX_PATH];
  char posix[MAX_PATH];
  size_t directory = 0;
  size_t parent = 0;
  int status = executable_directory (exe_path, sizeof (exe_path), &directory,
				     &parent);
  if (status)
    return status;

  if (parent + sizeof (DLL_UNLOAD_RUNTIME_LEAF) > sizeof (posix))
    return 3;
  memcpy (posix, exe_path, parent);
  memcpy (posix + parent, DLL_UNLOAD_RUNTIME_LEAF,
	  sizeof (DLL_UNLOAD_RUNTIME_LEAF));

  if (cygwin_conv_path (CCP_POSIX_TO_WIN_A | CCP_ABSOLUTE, posix, out, size))
    return 4;
  return 0;
}

/* When the harness exports runtime_root, require it to name the very same
   file.  This never relaxes the derivation above; it only adds a second
   independent agreement when the variable is available.  */
static int
crosscheck_runtime_root (const char *expected_win32_path, int *checked)
{
  static const char leaf[] = "/" DLL_UNLOAD_RUNTIME_NAME;
  struct file_identity from_root;
  struct file_identity expected;
  char posix[MAX_PATH];
  char win32[MAX_PATH];
  const char *root = getenv ("runtime_root");
  size_t length;

  *checked = 0;
  if (!root || !*root)
    return 0;
  length = strlen (root);
  if (length + sizeof (leaf) > sizeof (posix))
    return 1;
  memcpy (posix, root, length);
  memcpy (posix + length, leaf, sizeof (leaf));
  if (cygwin_conv_path (CCP_POSIX_TO_WIN_A | CCP_ABSOLUTE, posix, win32,
			sizeof (win32)))
    return 2;
  if (!query_identity (win32, &from_root)
      || !query_identity (expected_win32_path, &expected))
    return 3;
  if (!same_file (&from_root, &expected))
    return 4;
  *checked = 1;
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

/* Build a decoy file that shares the runtime base name in an unrelated
   directory, so the identity binding can be shown to reject it.  */
static int
make_decoy_runtime (char *directory, size_t directory_size, char *file,
		    size_t file_size)
{
  char temp[MAX_PATH];
  HANDLE handle;
  int written;

  if (!GetTempPathA (sizeof (temp), temp))
    return 1;
  written = snprintf (directory, directory_size, "%sdlu-decoy-%lu", temp,
		      (unsigned long) GetCurrentProcessId ());
  if (written < 0 || (size_t) written >= directory_size)
    return 2;
  if (!CreateDirectoryA (directory, NULL)
      && GetLastError () != ERROR_ALREADY_EXISTS)
    return 3;
  written = snprintf (file, file_size, "%s\\%s", directory,
		      DLL_UNLOAD_RUNTIME_NAME);
  if (written < 0 || (size_t) written >= file_size)
    return 4;
  handle = CreateFileA (file, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS,
			FILE_ATTRIBUTE_NORMAL, NULL);
  if (handle == INVALID_HANDLE_VALUE)
    return 5;
  CloseHandle (handle);
  return 0;
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
  path_fn loaded_path
    = (path_fn) dlsym (module, "dll_unload_loaded_runtime_path");
  identity_fn identity
    = (identity_fn) dlsym (module, "dll_unload_runtime_identity");
  bound_fn is_bound
    = (bound_fn) dlsym (module, "dll_unload_path_is_bound_runtime");
  if (!register_callbacks || !touch || !exported_addr || !static_addr
      || !loaded_path || !identity || !is_bound)
    {
      fprintf (stderr, "dlsym failed: %s\n", dlerror ());
      dlclose (module);
      return 2;
    }

  int status = register_callbacks (helper_log_path, mode, exe_unload_callback,
				   runtime_win32_path);
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

  if (mode == DLL_UNLOAD_MODE_FULL && !runtime_records_emitted)
    {
      unsigned long volume = 0;
      unsigned long high = 0;
      unsigned long low = 0;
      char decoy_directory[MAX_PATH];
      char decoy_file[MAX_PATH];
      int decoy;

      if (identity (&volume, &high, &low) != 0)
	{
	  fprintf (stderr, "helper did not report a runtime identity\n");
	  dlclose (module);
	  return 10;
	}
      printf ("DIAG dll_unload runtime volume=%08lx index=%08lx%08lx"
	      " expected=", volume, high, low);
      print_token (runtime_win32_path);
      fputs (" loaded=", stdout);
      print_token (loaded_path ());
      fputs (" result=pass\n", stdout);
      printf ("DIAG dll_unload export resolved=%p static=%p distinct=1"
	      " result=pass\n", dll_exported, dll_static);

      if (is_bound (runtime_win32_path) != 0)
	{
	  fprintf (stderr, "bound runtime path was not recognised\n");
	  dlclose (module);
	  return 11;
	}
      decoy = make_decoy_runtime (decoy_directory, sizeof (decoy_directory),
				  decoy_file, sizeof (decoy_file));
      if (decoy != 0)
	{
	  fprintf (stderr, "decoy runtime creation failed: %d\n", decoy);
	  dlclose (module);
	  return 12;
	}
      decoy = is_bound (decoy_file);
      DeleteFileA (decoy_file);
      RemoveDirectoryA (decoy_directory);
      if (decoy != 1)
	{
	  fprintf (stderr,
		   "decoy %s sharing the runtime base name was not rejected"
		   " (%d)\n", decoy_file, decoy);
	  dlclose (module);
	  return 13;
	}
      printf ("DIAG dll_unload control=wrong-path-same-basename rejected=1"
	      " decoy=");
      print_token (decoy_file);
      fputs (" result=pass\n", stdout);
      ++controls_passed;
      runtime_records_emitted = 1;
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
  int root_checked = 0;
  int cycles = 0;
  int status;

  setvbuf (stdout, NULL, _IOLBF, 0);

  status = derive_helper_path (helper_path, sizeof (helper_path));
  if (status)
    {
      fprintf (stderr, "helper path derivation failed: %d\n", status);
      return 1;
    }

  status = derive_runtime_path (runtime_win32_path,
				sizeof (runtime_win32_path));
  if (status)
    {
      fprintf (stderr, "runtime path derivation failed: %d\n", status);
      return 2;
    }

  status = crosscheck_runtime_root (runtime_win32_path, &root_checked);
  if (status)
    {
      fprintf (stderr, "runtime_root cross-check failed: %d\n", status);
      return 3;
    }
  printf ("DIAG dll_unload runtime_root_crosscheck performed=%d result=pass\n",
	  root_checked);

  status = resolve_runtime_atexit (runtime_win32_path, &exe_runtime_atexit);
  if (status)
    {
      fprintf (stderr, "runtime atexit export resolution failed: %d\n",
	       status);
      return 4;
    }

  if (!GetTempPathA (sizeof (temp_directory), temp_directory)
      || !GetTempFileNameA (temp_directory, "dlu", 0, positive_log)
      || !GetTempFileNameA (temp_directory, "dln", 0, negative_log))
    {
      fprintf (stderr, "failed to create lifecycle logs: %lu\n",
	       GetLastError ());
      return 5;
    }

  int result = 0;

  memcpy (helper_log_path, positive_log, strlen (positive_log) + 1);
  for (int iteration = 0; iteration < 2; ++iteration)
    {
      status = load_once (helper_path, DLL_UNLOAD_MODE_FULL);
      if (status)
	{
	  result = 20 + status;
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
	  result = 40 + iteration;
	  break;
	}

      if (misassociated_runs != 0)
	{
	  fprintf (stderr,
		   "mis-associated callback ran during unload %d\n",
		   iteration + 1);
	  result = 50 + iteration;
	  break;
	}
      ++cycles;
      printf ("DIAG dll_unload cycle=%d observed=%s expected_unit=%s"
	      " repeats=%d result=pass\n",
	      iteration + 1, actual, expected_full, iteration + 1);
    }

  /* Negative control: with the runtime-export registrations omitted the
     sequence must be exactly the reduced one and must be rejected by the
     same verifier the positive phase uses.  */
  if (result == 0)
    {
      memcpy (helper_log_path, negative_log, strlen (negative_log) + 1);
      status = load_once (helper_path, DLL_UNLOAD_MODE_OMIT_EXPORTED);
      if (status)
	result = 60 + status;
      else
	{
	  int length = read_log (negative_log, actual, sizeof (actual));
	  if (length < 0)
	    {
	      fprintf (stderr, "omitted-registration control log unreadable\n");
	      result = 70;
	    }
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
	  else
	    {
	      ++controls_passed;
	      printf ("DIAG dll_unload control=omit observed=%s expected=%s"
		      " positive_rejected=1 result=pass\n",
		      actual, expected_omit);
	      ++controls_passed;
	      printf ("DIAG dll_unload control=misassociated replayed=%d"
		      " result=pass\n", misassociated_runs);
	    }
	}
    }

  DeleteFileA (positive_log);
  DeleteFileA (negative_log);

  if (result == 0)
    printf ("DIAG dll_unload summary cycles=%d controls=%d result=pass\n",
	    cycles, controls_passed);
  fflush (stdout);
  return result;
}
