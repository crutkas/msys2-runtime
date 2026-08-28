/* Verify Cygwin-aware DLL finalizers and list teardown across reloads.

   The helper DLL registers unload callbacks through four distinct
   mechanisms and this program checks the exact marker sequence the runtime
   replays.  See winsup.api/dll_unload_helper.c for the marker vocabulary.

   Negative and alias controls run inside this test so a passing result cannot
   be vacuous:

     * an omitted-registration variant, which proves the positive marker
       expectation is falsifiable rather than trivially satisfied,
     * a mis-associated registration, made through the very same runtime
       export but from executable code, which must never be replayed when
       the helper DLL is unloaded, and
     * a decoy file and a hardlink spelling, which must not satisfy the
       final-path-plus-file-index binding, and
     * case, path-prefix, file-symlink, directory-junction and directory
       reparse spellings, which must canonicalise back to the bound file.

   Every check emits a machine-readable DIAG record on success as well as on
   failure, so a passing run carries its own evidence.  */

#include <windows.h>
#include <ctype.h>
#include <dlfcn.h>
#include <stddef.h>
#include <sys/cygwin.h>
#include <sys/stat.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <unistd.h>
#include <wchar.h>

/* Registration modes.  winsup.api/dll_unload_helper.c mirrors these. */
#define DLL_UNLOAD_MODE_FULL 0u
#define DLL_UNLOAD_MODE_OMIT_EXPORTED 1u

#define DLL_UNLOAD_RUNTIME_NAME "msys-2.0.dll"
#define DLL_UNLOAD_HELPER_LEAF "/dll_unload_helper.dll"
#define DLL_UNLOAD_RUNTIME_LEAF "/../testinst/bin/" DLL_UNLOAD_RUNTIME_NAME
#define ARRAY_SIZE(a) (sizeof (a) / sizeof ((a)[0]))

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
typedef int (*identity_fn) (unsigned long *, unsigned long *, unsigned long *,
			    int *, int *);
typedef int (*bound_fn) (const char *);
typedef int (*atexit_export_fn) (void (*) (void));
typedef DWORD (WINAPI *final_path_fn) (HANDLE, LPSTR, DWORD, DWORD);
typedef BOOLEAN (WINAPI *symbolic_link_fn) (LPCSTR, LPCSTR, DWORD);

#ifndef SYMBOLIC_LINK_FLAG_DIRECTORY
#define SYMBOLIC_LINK_FLAG_DIRECTORY 0x1
#endif
#ifndef SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE
#define SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE 0x2
#endif
#ifndef FILE_FLAG_OPEN_REPARSE_POINT
#define FILE_FLAG_OPEN_REPARSE_POINT 0x00200000
#endif
#ifndef IO_REPARSE_TAG_MOUNT_POINT
#define IO_REPARSE_TAG_MOUNT_POINT 0xa0000003
#endif
#ifndef FSCTL_SET_REPARSE_POINT
#define FSCTL_SET_REPARSE_POINT 0x000900a4
#endif
#ifndef FSCTL_DELETE_REPARSE_POINT
#define FSCTL_DELETE_REPARSE_POINT 0x000900ac
#endif

struct junction_reparse_buffer
{
  DWORD tag;
  WORD data_length;
  WORD reserved;
  WORD substitute_offset;
  WORD substitute_length;
  WORD print_offset;
  WORD print_length;
  WCHAR path_buffer[2 * MAX_PATH + 16];
};

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

static symbolic_link_fn
resolve_symbolic_link (void)
{
  static symbolic_link_fn cached;

  if (!cached)
    {
      HMODULE kernel = GetModuleHandleA ("kernel32.dll");
      if (kernel)
	cached = (symbolic_link_fn) (void *)
	  GetProcAddress (kernel, "CreateSymbolicLinkA");
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

static char helper_log_path[MAX_PATH];
static char runtime_win32_path[MAX_PATH];
static atexit_export_fn exe_runtime_atexit;
static struct file_identity expected_runtime_identity;
static struct file_identity loaded_runtime_identity;
static volatile int misassociated_runs;
static int controls_passed;
static int runtime_records_emitted;

struct identity_fixtures
{
  char root[MAX_PATH];
  char decoy[MAX_PATH];
  char hardlink[MAX_PATH];
  char file_symlink[MAX_PATH];
  char junction[MAX_PATH];
  char junction_runtime[MAX_PATH];
  char reparse[MAX_PATH];
  char reparse_runtime[MAX_PATH];
  char case_path[MAX_PATH];
  char prefix_path[MAX_PATH];
  int root_created;
  int decoy_created;
  int hardlink_created;
  int file_symlink_created;
  int junction_created;
  int reparse_created;
};

static struct identity_fixtures identity_fixtures;

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

/* Mirrors the helper resolution so the two results can be compared. */
static int
resolve_runtime_atexit (const char *expected_win32_path,
			atexit_export_fn *out)
{
  MEMORY_BASIC_INFORMATION info;
  char module_path[MAX_PATH];
  HMODULE runtime;
  FARPROC entry;
  DWORD length;

  if (!query_identity (expected_win32_path, &expected_runtime_identity))
    return 1;
  runtime = GetModuleHandleA (DLL_UNLOAD_RUNTIME_NAME);
  if (!runtime)
    {
      close_identity (&expected_runtime_identity);
      return 2;
    }
  length = GetModuleFileNameA (runtime, module_path, sizeof (module_path));
  if (length == 0 || length >= sizeof (module_path))
    {
      close_identity (&expected_runtime_identity);
      return 3;
    }
  if (!query_identity (module_path, &loaded_runtime_identity))
    {
      close_identity (&expected_runtime_identity);
      return 4;
    }
  if (!same_file (&expected_runtime_identity, &loaded_runtime_identity))
    {
      close_identity (&loaded_runtime_identity);
      close_identity (&expected_runtime_identity);
      return 5;
    }
  entry = GetProcAddress (runtime, "atexit");
  if (!entry)
    {
      close_identity (&loaded_runtime_identity);
      close_identity (&expected_runtime_identity);
      return 6;
    }
  memset (&info, 0, sizeof (info));
  if (VirtualQuery ((const void *) entry, &info, sizeof (info))
      != sizeof (info))
    {
      close_identity (&loaded_runtime_identity);
      close_identity (&expected_runtime_identity);
      return 7;
    }
  if (info.AllocationBase != (void *) runtime)
    {
      close_identity (&loaded_runtime_identity);
      close_identity (&expected_runtime_identity);
      return 8;
    }
  if ((void *) entry == (void *) &atexit)
    {
      close_identity (&loaded_runtime_identity);
      close_identity (&expected_runtime_identity);
      return 9;
    }
  *out = (atexit_export_fn) (void *) entry;
  return 0;
}

/* Locate the directory of the running executable, returning the offset of
   the separator that ends it.  The runtime lives one level up, but that is
   expressed with a relative component rather than by counting separators,
   so the derivation does not depend on how deep the build tree happens to
   be; the handle-based canonicalisation resolves it.  */
static int
executable_directory (char *out, size_t size, size_t *directory)
{
  ssize_t length = readlink ("/proc/self/exe", out, size - 1);
  size_t found = 0;

  if (length <= 0 || (size_t) length >= size)
    return 1;
  out[length] = '\0';

  for (size_t i = 0; i < (size_t) length; ++i)
    if (out[i] == '/' || out[i] == '\\')
      found = i;
  if (found == 0)
    return 2;
  *directory = found;
  return 0;
}

static int
derive_helper_path (char *out, size_t size)
{
  char exe_path[MAX_PATH];
  size_t directory = 0;
  struct stat helper;
  int status = executable_directory (exe_path, sizeof (exe_path), &directory);

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
   <testsuite builddir>/testinst/bin, which sits beside the directory holding
   this executable.  That layout is trusted harness state, so the expected
   path is derived from it rather than from PATH.  The relative component is
   resolved by the handle-based canonicalisation below.  */
static int
derive_runtime_path (char *out, size_t size)
{
  char exe_path[MAX_PATH];
  char posix[MAX_PATH];
  size_t directory = 0;
  int status = executable_directory (exe_path, sizeof (exe_path), &directory);

  if (status)
    return status;

  if (directory + sizeof (DLL_UNLOAD_RUNTIME_LEAF) > sizeof (posix))
    return 3;
  memcpy (posix, exe_path, directory);
  memcpy (posix + directory, DLL_UNLOAD_RUNTIME_LEAF,
	  sizeof (DLL_UNLOAD_RUNTIME_LEAF));

  if (cygwin_conv_path (CCP_POSIX_TO_WIN_A | CCP_ABSOLUTE, posix, out, size))
    return 4;
  return 0;
}

/* The harness-provided runtime_root must name the very same file.  This never
   relaxes the source-derived path above; it adds a mandatory second agreement
   from independently supplied harness state.  */
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
    return 1;
  length = strlen (root);
  if (length + sizeof (leaf) > sizeof (posix))
    return 2;
  memcpy (posix, root, length);
  memcpy (posix + length, leaf, sizeof (leaf));
  if (cygwin_conv_path (CCP_POSIX_TO_WIN_A | CCP_ABSOLUTE, posix, win32,
			sizeof (win32)))
    return 3;
  if (!query_identity (win32, &from_root))
    return 4;
  if (!query_identity (expected_win32_path, &expected))
    {
      close_identity (&from_root);
      return 4;
    }
  if (!same_file (&from_root, &expected))
    {
      close_identity (&expected);
      close_identity (&from_root);
      return 5;
    }
  close_identity (&expected);
  close_identity (&from_root);
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

static int
join_path (char *out, size_t size, const char *directory, const char *leaf)
{
  int written = snprintf (out, size, "%s\\%s", directory, leaf);
  return written >= 0 && (size_t) written < size;
}

static int
create_empty_file (const char *path)
{
  HANDLE handle = CreateFileA (path, GENERIC_WRITE, 0, NULL, CREATE_NEW,
			       FILE_ATTRIBUTE_NORMAL, NULL);
  if (handle == INVALID_HANDLE_VALUE)
    return 0;
  CloseHandle (handle);
  return 1;
}

static int
create_native_symlink (const char *link, const char *target, DWORD flags)
{
  symbolic_link_fn create = resolve_symbolic_link ();

  if (!create)
    return 0;
  if (create (link, target,
	      flags | SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE))
    return 1;
  if (create (link, target, flags))
    return 1;
  return 0;
}

static int
create_junction (const char *link, const char *target)
{
  struct junction_reparse_buffer buffer;
  WCHAR target_w[MAX_PATH];
  WCHAR substitute[MAX_PATH + 4];
  const char *dos_target = target;
  DWORD returned;
  HANDLE directory;
  size_t substitute_bytes;
  size_t print_bytes;
  DWORD input_size;

  if (strncmp (dos_target, "\\\\?\\", 4) == 0)
    dos_target += 4;
  if (!MultiByteToWideChar (CP_ACP, 0, dos_target, -1, target_w,
			    (int) ARRAY_SIZE (target_w)))
    return 0;
  if (swprintf (substitute, ARRAY_SIZE (substitute), L"\\??\\%ls",
		target_w) < 0)
    return 0;
  if (!CreateDirectoryA (link, NULL))
    return 0;

  directory = CreateFileA (
    link, GENERIC_WRITE, 0, NULL, OPEN_EXISTING,
    FILE_FLAG_OPEN_REPARSE_POINT | FILE_FLAG_BACKUP_SEMANTICS, NULL);
  if (directory == INVALID_HANDLE_VALUE)
    {
      RemoveDirectoryA (link);
      return 0;
    }

  memset (&buffer, 0, sizeof (buffer));
  substitute_bytes = wcslen (substitute) * sizeof (WCHAR);
  print_bytes = wcslen (target_w) * sizeof (WCHAR);
  if (substitute_bytes + sizeof (WCHAR) + print_bytes + sizeof (WCHAR)
      > sizeof (buffer.path_buffer))
    {
      CloseHandle (directory);
      RemoveDirectoryA (link);
      return 0;
    }
  buffer.tag = IO_REPARSE_TAG_MOUNT_POINT;
  buffer.substitute_offset = 0;
  buffer.substitute_length = (WORD) substitute_bytes;
  buffer.print_offset = (WORD) (substitute_bytes + sizeof (WCHAR));
  buffer.print_length = (WORD) print_bytes;
  memcpy (buffer.path_buffer, substitute, substitute_bytes + sizeof (WCHAR));
  memcpy ((char *) buffer.path_buffer + buffer.print_offset, target_w,
	  print_bytes + sizeof (WCHAR));
  buffer.data_length = (WORD) (
    4 * sizeof (WORD) + substitute_bytes + sizeof (WCHAR)
    + print_bytes + sizeof (WCHAR));
  input_size = 8 + buffer.data_length;

  BOOL ok = DeviceIoControl (directory, FSCTL_SET_REPARSE_POINT,
			     &buffer, input_size, NULL, 0, &returned, NULL);
  CloseHandle (directory);
  if (!ok)
    RemoveDirectoryA (link);
  return ok != 0;
}

static int
delete_junction (const char *path)
{
  struct
  {
    DWORD tag;
    WORD data_length;
    WORD reserved;
  } buffer;
  DWORD returned;
  HANDLE directory = CreateFileA (
    path, GENERIC_WRITE, 0, NULL, OPEN_EXISTING,
    FILE_FLAG_OPEN_REPARSE_POINT | FILE_FLAG_BACKUP_SEMANTICS, NULL);

  if (directory == INVALID_HANDLE_VALUE)
    return 0;
  memset (&buffer, 0, sizeof (buffer));
  buffer.tag = IO_REPARSE_TAG_MOUNT_POINT;
  BOOL ok = DeviceIoControl (directory, FSCTL_DELETE_REPARSE_POINT,
			     &buffer, sizeof (buffer), NULL, 0, &returned, NULL);
  CloseHandle (directory);
  return ok && RemoveDirectoryA (path);
}

static int
cleanup_identity_fixtures (void)
{
  int ok = 1;

  if (identity_fixtures.reparse_created)
    ok = RemoveDirectoryA (identity_fixtures.reparse) && ok;
  if (identity_fixtures.junction_created)
    ok = delete_junction (identity_fixtures.junction) && ok;
  if (identity_fixtures.file_symlink_created)
    ok = DeleteFileA (identity_fixtures.file_symlink) && ok;
  if (identity_fixtures.hardlink_created)
    ok = DeleteFileA (identity_fixtures.hardlink) && ok;
  if (identity_fixtures.decoy_created)
    ok = DeleteFileA (identity_fixtures.decoy) && ok;
  if (identity_fixtures.root_created)
    ok = RemoveDirectoryA (identity_fixtures.root) && ok;
  memset (&identity_fixtures, 0, sizeof (identity_fixtures));
  return ok;
}

static int
setup_identity_fixtures (const char *runtime)
{
  char fixture_parent[MAX_PATH];
  char runtime_directory[MAX_PATH];
  char *separator;
  int written;

  memset (&identity_fixtures, 0, sizeof (identity_fixtures));
  if (strlen (runtime) >= sizeof (runtime_directory))
    return 1;
  strcpy (runtime_directory, runtime);
  separator = strrchr (runtime_directory, '\\');
  if (!separator)
    separator = strrchr (runtime_directory, '/');
  if (!separator || separator == runtime_directory)
    return 1;
  *separator = '\0';
  strcpy (fixture_parent, runtime_directory);
  separator = strrchr (fixture_parent, '\\');
  if (!separator)
    separator = strrchr (fixture_parent, '/');
  if (!separator || separator == fixture_parent)
    return 1;
  *separator = '\0';

  written = snprintf (
    identity_fixtures.root, sizeof (identity_fixtures.root),
    "%s\\dlu-alias-%lu-%lu", fixture_parent,
    (unsigned long) GetCurrentProcessId (), (unsigned long) GetTickCount ());
  if (written < 0 || (size_t) written >= sizeof (identity_fixtures.root))
    return 2;
  if (!CreateDirectoryA (identity_fixtures.root, NULL))
    return 3;
  identity_fixtures.root_created = 1;

  if (!join_path (identity_fixtures.decoy, sizeof (identity_fixtures.decoy),
		  identity_fixtures.root, DLL_UNLOAD_RUNTIME_NAME)
      || !join_path (identity_fixtures.hardlink,
		     sizeof (identity_fixtures.hardlink),
		     identity_fixtures.root, "hardlink-msys-2.0.dll")
      || !join_path (identity_fixtures.file_symlink,
		     sizeof (identity_fixtures.file_symlink),
		     identity_fixtures.root, "symlink-msys-2.0.dll")
      || !join_path (identity_fixtures.junction,
		     sizeof (identity_fixtures.junction),
		     identity_fixtures.root, "junction")
      || !join_path (identity_fixtures.reparse,
		     sizeof (identity_fixtures.reparse),
		     identity_fixtures.root, "directory-symlink"))
    goto path_failure;

  if (!create_empty_file (identity_fixtures.decoy))
    goto create_failure;
  identity_fixtures.decoy_created = 1;
  if (!CreateHardLinkA (identity_fixtures.hardlink, runtime, NULL))
    goto create_failure;
  identity_fixtures.hardlink_created = 1;
  if (!create_native_symlink (identity_fixtures.file_symlink, runtime, 0))
    goto create_failure;
  identity_fixtures.file_symlink_created = 1;

  if (!create_junction (identity_fixtures.junction, runtime_directory))
    goto create_failure;
  identity_fixtures.junction_created = 1;
  if (!join_path (identity_fixtures.junction_runtime,
		  sizeof (identity_fixtures.junction_runtime),
		  identity_fixtures.junction, DLL_UNLOAD_RUNTIME_NAME))
    goto path_failure;

  if (!create_native_symlink (identity_fixtures.reparse, runtime_directory,
			      SYMBOLIC_LINK_FLAG_DIRECTORY))
    goto create_failure;
  identity_fixtures.reparse_created = 1;
  if (!join_path (identity_fixtures.reparse_runtime,
		  sizeof (identity_fixtures.reparse_runtime),
		  identity_fixtures.reparse, DLL_UNLOAD_RUNTIME_NAME))
    goto path_failure;

  if (strlen (runtime) >= sizeof (identity_fixtures.case_path))
    goto path_failure;
  strcpy (identity_fixtures.case_path, runtime);
  for (char *p = identity_fixtures.case_path; *p; ++p)
    if (isalpha ((unsigned char) *p))
      {
	*p = islower ((unsigned char) *p) ? toupper ((unsigned char) *p)
					 : tolower ((unsigned char) *p);
	break;
      }

  if (strncmp (runtime, "\\\\?\\UNC\\", 8) == 0)
    written = snprintf (identity_fixtures.prefix_path,
			sizeof (identity_fixtures.prefix_path), "\\\\%s",
			runtime + 8);
  else if (strncmp (runtime, "\\\\?\\", 4) == 0)
    written = snprintf (identity_fixtures.prefix_path,
			sizeof (identity_fixtures.prefix_path), "%s",
			runtime + 4);
  else if (strncmp (runtime, "\\\\", 2) == 0)
    written = snprintf (identity_fixtures.prefix_path,
			sizeof (identity_fixtures.prefix_path), "\\\\?\\UNC\\%s",
			runtime + 2);
  else
    written = snprintf (identity_fixtures.prefix_path,
			sizeof (identity_fixtures.prefix_path), "\\\\?\\%s",
			runtime);
  if (written < 0
      || (size_t) written >= sizeof (identity_fixtures.prefix_path))
    goto path_failure;
  return 0;

path_failure:
  return cleanup_identity_fixtures () ? 4 : 6;
create_failure:
  return cleanup_identity_fixtures () ? 5 : 6;
}

static const char *
binding_result (int status)
{
  if (status == 0)
    return "bound";
  if (status == 1)
    return "rejected";
  return "unavailable";
}

static int
run_binding_control (bound_fn is_bound, const char *name, const char *path,
		     int expected)
{
  int observed = is_bound (path);

  if (observed != expected)
    {
      fprintf (stderr,
	       "identity control %s expected %s, observed %s (%d) for %s\n",
	       name, binding_result (expected), binding_result (observed),
	       observed, path);
      return 0;
    }
  printf ("DIAG dll_unload control=%s expected=%s observed=%s path=",
	  name, binding_result (expected), binding_result (observed));
  print_token (path);
  fputs (" result=pass\n", stdout);
  ++controls_passed;
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
  path_fn loaded_path
    = (path_fn) dlsym (module, "dll_unload_loaded_runtime_path");
  path_fn loaded_final
    = (path_fn) dlsym (module, "dll_unload_loaded_runtime_final_path");
  identity_fn identity
    = (identity_fn) dlsym (module, "dll_unload_runtime_identity");
  bound_fn is_bound
    = (bound_fn) dlsym (module, "dll_unload_path_is_bound_runtime");
  if (!register_callbacks || !touch || !exported_addr || !static_addr
      || !loaded_path || !loaded_final || !identity || !is_bound)
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
      int expected_open = 0;
      int loaded_open = 0;

      if (identity (&volume, &high, &low, &expected_open, &loaded_open) != 0
	  || expected_open != 1 || loaded_open != 1
	  || !identity_open (&expected_runtime_identity)
	  || !identity_open (&loaded_runtime_identity))
	{
	  fprintf (stderr, "runtime identity handles are not open\n");
	  dlclose (module);
	  return 10;
	}
      if (volume != (unsigned long) loaded_runtime_identity.volume
	  || high != (unsigned long) loaded_runtime_identity.index_high
	  || low != (unsigned long) loaded_runtime_identity.index_low)
	{
	  fprintf (stderr, "helper and executable runtime identities differ\n");
	  dlclose (module);
	  return 11;
	}
      printf ("DIAG dll_unload runtime volume=%08lx index=%08lx%08lx"
	      " expected=", volume, high, low);
      print_token (runtime_win32_path);
      fputs (" loaded=", stdout);
      print_token (loaded_path ());
      fputs (" final=", stdout);
      print_token (loaded_final ());
      fputs (" expected_handle_open=1 loaded_handle_open=1"
	     " delete_share=0 result=pass\n", stdout);
      printf ("DIAG dll_unload export resolved=%p static=%p distinct=1"
	      " result=pass\n", dll_exported, dll_static);

      if (is_bound (runtime_win32_path) != 0)
	{
	  fprintf (stderr, "bound runtime path was not recognised\n");
	  dlclose (module);
	  return 12;
	}
      const struct
      {
	const char *name;
	const char *path;
	int expected;
      } controls[] = {
	{ "wrong-path-same-basename", identity_fixtures.decoy, 1 },
	{ "path-case", identity_fixtures.case_path, 0 },
	{ "path-prefix", identity_fixtures.prefix_path, 0 },
	{ "hardlink-alias", identity_fixtures.hardlink, 1 },
	{ "file-symlink", identity_fixtures.file_symlink, 0 },
	{ "directory-junction", identity_fixtures.junction_runtime, 0 },
	{ "directory-symlink-reparse", identity_fixtures.reparse_runtime, 0 },
      };
      for (size_t i = 0; i < ARRAY_SIZE (controls); ++i)
	if (!run_binding_control (is_bound, controls[i].name,
				  controls[i].path, controls[i].expected))
	  {
	    dlclose (module);
	    return 13;
	  }
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

  {
    /* Emit the derived layout first, so any derivation failure below is
       self-explaining rather than needing another run to diagnose.  */
    char exe[MAX_PATH];
    ssize_t seen = readlink ("/proc/self/exe", exe, sizeof (exe) - 1);

    if (seen > 0 && (size_t) seen < sizeof (exe))
      {
	exe[seen] = '\0';
	fputs ("DIAG dll_unload executable path=", stdout);
	print_token (exe);
	fputs (" result=pass\n", stdout);
      }
  }

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
  printf ("DIAG dll_unload derived helper=");
  print_token (helper_path);
  fputs (" runtime=", stdout);
  print_token (runtime_win32_path);
  fputs (" result=pass\n", stdout);

  status = crosscheck_runtime_root (runtime_win32_path, &root_checked);
  if (status)
    {
      fprintf (stderr, "runtime_root cross-check failed: %d\n", status);
      return 3;
    }
  printf ("DIAG dll_unload runtime_root_crosscheck performed=%d result=pass\n",
	  root_checked);

  status = setup_identity_fixtures (runtime_win32_path);
  if (status)
    {
      fprintf (stderr, "runtime identity fixture setup failed: %d\n", status);
      return 4;
    }

  status = resolve_runtime_atexit (runtime_win32_path, &exe_runtime_atexit);
  if (status)
    {
      char module_path[MAX_PATH];
      HMODULE runtime = GetModuleHandleA (DLL_UNLOAD_RUNTIME_NAME);

      module_path[0] = '\0';
      if (runtime)
	GetModuleFileNameA (runtime, module_path, sizeof (module_path));
      fprintf (stderr,
	       "runtime atexit export resolution failed: %d"
	       " (expected \"%s\", loaded \"%s\")\n",
	       status, runtime_win32_path, module_path);
      if (!cleanup_identity_fixtures ())
	fprintf (stderr, "runtime identity fixture cleanup also failed\n");
      return 5;
    }

  if (!GetTempPathA (sizeof (temp_directory), temp_directory)
      || !GetTempFileNameA (temp_directory, "dlu", 0, positive_log)
      || !GetTempFileNameA (temp_directory, "dln", 0, negative_log))
    {
      fprintf (stderr, "failed to create lifecycle logs: %lu\n",
	       GetLastError ());
      close_identity (&loaded_runtime_identity);
      close_identity (&expected_runtime_identity);
      if (!cleanup_identity_fixtures ())
	fprintf (stderr, "runtime identity fixture cleanup also failed\n");
      return 6;
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

  int cleanup_ok = 1;
  if (!DeleteFileA (positive_log))
    {
      fprintf (stderr, "failed to remove positive lifecycle log: %lu\n",
	       GetLastError ());
      cleanup_ok = 0;
    }
  if (!DeleteFileA (negative_log))
    {
      fprintf (stderr, "failed to remove negative lifecycle log: %lu\n",
	       GetLastError ());
      cleanup_ok = 0;
    }
  close_identity (&loaded_runtime_identity);
  close_identity (&expected_runtime_identity);
  if (!cleanup_identity_fixtures ())
    {
      fprintf (stderr, "failed to remove runtime identity fixtures\n");
      cleanup_ok = 0;
    }
  if (result == 0 && !cleanup_ok)
    result = 80;

  if (result == 0)
    printf ("DIAG dll_unload summary cycles=%d controls=%d result=pass\n",
	    cycles, controls_passed);
  fflush (stdout);
  return result;
}
