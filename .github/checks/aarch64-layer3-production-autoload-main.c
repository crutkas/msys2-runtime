#include <stdint.h>

typedef struct { uint64_t opaque[8]; } fenv_t;
typedef uint16_t WCHAR;
typedef void *HANDLE;

__declspec(dllimport) void ExitProcess (unsigned long);
__declspec(dllimport) unsigned long GetEnvironmentVariableA (
  const char *, char *, unsigned long);
__declspec(dllimport) unsigned long GetLastError (void);
__declspec(dllimport) void SetLastError (unsigned long);
__declspec(dllimport) HANDLE GetModuleHandleW (const WCHAR *);
__declspec(dllimport) void *GetProcAddress (HANDLE, const char *);

long layer3_import_add (long);
long layer3_missing_optional (void);
long layer3_missing_fatal (void);
long layer3_absent_optional (void);
long layer3_absent_fatal (void);
void layer3_control_set_import_here (int32_t);
void layer3_control_set_import_handle (HANDLE);
int32_t layer3_control_import_here (void);
_Bool layer3_control_wsock_started (void);

WCHAR windows_system_directory[260]
  = { 'C', ':', '\\', 's', 'y', 's', 't', 'e', 'm', '\\', 0 };

static char layer3_mode;
static int layer3_full_path_calls;
static int layer3_bare_name_calls;
static int layer3_yield_calls;
static int layer3_fegetenv_calls;
static int layer3_fesetenv_calls;
static int layer3_interlocked_increment_calls;
static int layer3_interlocked_decrement_calls;
static int layer3_debug_calls;

static HANDLE
kernel_load_library (const WCHAR *name)
{
  static const WCHAR kernel32_name[]
    = { 'k', 'e', 'r', 'n', 'e', 'l', '3', '2', '.', 'd', 'l', 'l', 0 };
  typedef HANDLE (*load_library_w_fn) (const WCHAR *);
  HANDLE kernel32 = GetModuleHandleW (kernel32_name);
  load_library_w_fn load_library
    = (load_library_w_fn) GetProcAddress (kernel32, "LoadLibraryW");
  return load_library (name);
}

static int
is_bare_name (const WCHAR *name)
{
  while (*name)
    if (*name++ == '\\')
      return 0;
  return 1;
}

WCHAR *
wcpcpy (WCHAR *destination, const WCHAR *source)
{
  while ((*destination = *source++) != 0)
    ++destination;
  return destination;
}

HANDLE
LoadLibraryW (const WCHAR *name)
{
  if (!is_bare_name (name))
    {
      ++layer3_full_path_calls;
      SetLastError (126);
      return 0;
    }

  ++layer3_bare_name_calls;
  if (layer3_bare_name_calls == 1
      && (layer3_mode == 'a' || layer3_mode == 'd'))
    {
      SetLastError (layer3_mode == 'a' ? 998 : 1114);
      return 0;
    }

  return kernel_load_library (name);
}

int32_t
InterlockedIncrement (volatile int32_t *value)
{
  ++layer3_interlocked_increment_calls;
  return ++*value;
}

int32_t
InterlockedDecrement (volatile int32_t *value)
{
  ++layer3_interlocked_decrement_calls;
  return --*value;
}

void
yield (void)
{
  static const WCHAR import_name[]
    = { 'l', 'a', 'y', 'e', 'r', '3', '_', 'i', 'm', 'p', 'o', 'r', 't',
	'.', 'd', 'l', 'l', 0 };
  ++layer3_yield_calls;
  if (layer3_mode == 'g')
    {
      HANDLE handle = kernel_load_library (import_name);
      layer3_control_set_import_handle (handle);
      layer3_control_set_import_here (-1);
    }
}

int
fegetenv (fenv_t *environment)
{
  ++layer3_fegetenv_calls;
  environment->opaque[0] = 0;
  return 0;
}

int
fesetenv (const fenv_t *environment)
{
  (void) environment;
  ++layer3_fesetenv_calls;
  return 0;
}

void
layer3_debug_printf (const char *format, ...)
{
  (void) format;
  ++layer3_debug_calls;
}

void
api_fatal (const char *format, ...)
{
  (void) format;
  ExitProcess (91);
}

void
mainCRTStartup (void)
{
  char mode[16] = { 0 };
  GetEnvironmentVariableA ("LAYER3_AUTOLOAD_CASE", mode, sizeof mode);
  layer3_mode = mode[0];

  if (mode[0] == 'f')
    layer3_absent_fatal ();
  if (mode[0] == 'p')
    layer3_missing_fatal ();
  if (mode[0] == 'n')
    ExitProcess (layer3_missing_optional () == 73
		 && GetLastError () == 127 ? 0 : 2);
  if (mode[0] == 'l')
    ExitProcess (layer3_absent_optional () == 74
		 && GetLastError () == 127 ? 0 : 3);

  if (mode[0] == 'g')
    layer3_control_set_import_here (0);

  long first = layer3_import_add (5);
  long second = layer3_import_add (6);
  int common = first == 42 && second == 43
	       && layer3_control_wsock_started ()
	       && layer3_control_import_here () == -1;

  if (mode[0] == 'g')
    ExitProcess (common && layer3_yield_calls == 1
		 && layer3_full_path_calls == 0
		 && layer3_bare_name_calls == 0
		 && layer3_interlocked_increment_calls == 3
		 && layer3_interlocked_decrement_calls == 3
		 && layer3_debug_calls == 7 ? 0 : 4);
  if (mode[0] == 'a' || mode[0] == 'd')
    ExitProcess (common && layer3_yield_calls == 1
		 && layer3_full_path_calls == 2
		 && layer3_bare_name_calls == 2
		 && layer3_fegetenv_calls == 1
		 && layer3_fesetenv_calls == 1
		 && layer3_interlocked_increment_calls == 2
		 && layer3_interlocked_decrement_calls == 2
		 && layer3_debug_calls == 7 ? 0 : 5);
  ExitProcess (common && layer3_yield_calls == 0
	       && layer3_full_path_calls == 1
	       && layer3_bare_name_calls == 1
	       && layer3_fegetenv_calls == 1
	       && layer3_fesetenv_calls == 1
	       && layer3_interlocked_increment_calls == 2
	       && layer3_interlocked_decrement_calls == 2
	       && layer3_debug_calls == 7 ? 0 : 1);
}
