#include <stddef.h>
#include <stdint.h>
#include <windows.h>
#include <winternl.h>

#if !defined(__aarch64__)
#error This check must be compiled for AArch64
#endif

#if !defined(_WIN64)
#error This check requires the Windows 64-bit ABI
#endif

#if !defined(__LP64__)
#error This check requires the LP64 Cygwin data model
#endif

_Static_assert (sizeof (void *) == 8, "AArch64 runtime uses 64-bit pointers");
_Static_assert (sizeof (HANDLE) == sizeof (void *),
		"HANDLE must be pointer-sized");
_Static_assert (sizeof (UNICODE_STRING) == 16,
		"UNICODE_STRING layout mismatch");
_Static_assert (offsetof (UNICODE_STRING, Buffer) == 8,
		"UNICODE_STRING.Buffer offset mismatch");
_Static_assert (sizeof (OBJECT_NAME_INFORMATION) == sizeof (UNICODE_STRING),
		"OBJECT_NAME_INFORMATION layout mismatch");
_Static_assert (offsetof (OBJECT_NAME_INFORMATION, Name) == 0,
		"OBJECT_NAME_INFORMATION.Name offset mismatch");
_Static_assert (sizeof (LUID) == 8,
		"LUID layout mismatch");
_Static_assert (offsetof (LUID, HighPart) == 4,
		"LUID.HighPart offset mismatch");
_Static_assert (offsetof (FILE_ACCESS_INFORMATION, AccessFlags) == 0,
		"FILE_ACCESS_INFORMATION.AccessFlags offset mismatch");
_Static_assert (sizeof (FILE_ACCESS_INFORMATION) == sizeof (ACCESS_MASK),
		"FILE_ACCESS_INFORMATION size mismatch");

int
main (void)
{
  return 0;
}
