#define _WIN32_WINNT 0x0a00
#include <windows.h>
#include <stdint.h>

static HANDLE output;

static void
emit (const char *data, DWORD size)
{
  DWORD written;
  while (size)
    {
      if (!WriteFile (output, data, size, &written, NULL) || !written)
	ExitProcess (90);
      data += written;
      size -= written;
    }
}

static void
text (const char *s)
{
  const char *end = s;
  while (*end)
    ++end;
  emit (s, (DWORD) (end - s));
}

static void
decimal (size_t value)
{
  char buffer[32];
  char *p = buffer + sizeof buffer;
  do
    {
      *--p = (char) ('0' + value % 10);
      value /= 10;
    }
  while (value);
  emit (p, (DWORD) (buffer + sizeof buffer - p));
}

static void
hex_byte (unsigned int value)
{
  static const char digits[] = "0123456789abcdef";
  char pair[2] = {digits[(value >> 4) & 15], digits[value & 15]};
  emit (pair, 2);
}

static void
hex_bytes (const unsigned char *bytes, size_t size)
{
  for (size_t i = 0; i < size; ++i)
    hex_byte (bytes[i]);
}

static void
utf16 (const WCHAR *value)
{
  for (const WCHAR *p = value; p && *p; ++p)
    {
      hex_byte ((unsigned int) *p & 255);
      hex_byte ((unsigned int) *p >> 8);
    }
}

static void
module_info (const char *name, HMODULE module)
{
  WCHAR path[1024];
  DWORD size = module ? GetModuleFileNameW (module, path, 1024) : 0;
  text (name);
  text (".machine=");
  if (module)
    {
      IMAGE_DOS_HEADER *dos = (IMAGE_DOS_HEADER *) module;
      IMAGE_NT_HEADERS64 *nt = (IMAGE_NT_HEADERS64 *)
	((unsigned char *) module + dos->e_lfanew);
      hex_byte (nt->FileHeader.Machine >> 8);
      hex_byte (nt->FileHeader.Machine);
    }
  text ("\n");
  text (name);
  text (".path_utf16=");
  if (size && size < 1024)
    utf16 (path);
  text ("\n");
}

int
main (int argc, char **argv)
{
  typedef LPWSTR (WINAPI *get_command_line_w_type) (void);
  WCHAR path[MAX_PATH];
  char marker[128];
  WCHAR *runtime_command_line = GetCommandLineW ();
  USHORT process_machine = 0;
  USHORT native_machine = 0;
  HMODULE module = GetModuleHandleW (NULL);
  HMODULE kernel32 = GetModuleHandleW (L"kernel32.dll");
  get_command_line_w_type native_get_command_line =
    (get_command_line_w_type) GetProcAddress (kernel32, "GetCommandLineW");
  WCHAR *raw = native_get_command_line ? native_get_command_line () : NULL;

  DWORD path_size = GetEnvironmentVariableW (L"ARM64_ARGV_OUTPUT", path,
					      MAX_PATH);
  output = path_size && path_size < MAX_PATH
    ? CreateFileW (path, GENERIC_WRITE, FILE_SHARE_READ, NULL, CREATE_ALWAYS,
		   FILE_ATTRIBUTE_NORMAL, NULL)
    : GetStdHandle (STD_OUTPUT_HANDLE);
  if (output == INVALID_HANDLE_VALUE)
    return 91;

  if (!IsWow64Process2 (GetCurrentProcess (), &process_machine,
			&native_machine))
    return 92;
  text ("process_machine=");
  hex_byte (process_machine >> 8);
  hex_byte (process_machine);
  text ("\nnative_machine=");
  hex_byte (native_machine >> 8);
  hex_byte (native_machine);
  text ("\nraw_utf16=");
  utf16 (raw);
  text ("\nruntime_command_line_utf16=");
  utf16 (runtime_command_line);
  text ("\n");
  module_info ("module.main", module);
  module_info ("module.runtime", GetModuleHandleW (L"msys-2.0.dll"));
  module_info ("module.kernel32", kernel32);
  module_info ("module.libgcc",
	       GetModuleHandleW (L"msys-gcc_s-seh-1.dll"));
  text ("\nargc=");
  decimal ((size_t) argc);
  text ("\n");

  for (int i = 0; i < argc; ++i)
    {
      size_t length = 0;
      while (argv[i][length])
	++length;
      text ("arg.");
      decimal ((size_t) i);
      text (".len=");
      decimal (length);
      text ("\narg.");
      decimal ((size_t) i);
      text (".hex=");
      hex_bytes ((const unsigned char *) argv[i], length);
      text ("\n");
    }

  text ("environment=");
  DWORD marker_size = GetEnvironmentVariableA ("ARM64_ARGV_MARKER", marker,
						sizeof marker);
  if (marker_size && marker_size < sizeof marker)
    hex_bytes ((const unsigned char *) marker, marker_size);
  text ("\n");
  if (output != GetStdHandle (STD_OUTPUT_HANDLE))
    CloseHandle (output);
  return 0;
}
