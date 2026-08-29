#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdint.h>

void
sigdelayed_init (PCONTEXT context)
{
  const DWORD64 *saved = (const DWORD64 *) context->Sp;
  DWORD64 image_base = 0;
  PRUNTIME_FUNCTION function;
  CONTEXT unwound;
  PVOID handler_data = NULL;
  DWORD64 establisher_frame = 0;
  PEXCEPTION_ROUTINE handler;

  if ((context->Sp & 15) != 0
      || saved[0] != 0x1616
      || saved[1] != 0x1717
      || saved[2] != 0x1234
      || saved[3] == 0)
    ExitProcess (41);

  function = RtlLookupFunctionEntry (context->Pc, &image_base, NULL);
  if (!function)
    ExitProcess (42);

  unwound = *context;
  handler = RtlVirtualUnwind (UNW_FLAG_NHANDLER, image_base, context->Pc,
			      function, &unwound, &handler_data,
			      &establisher_frame, NULL);
  if (handler != NULL
      || unwound.Sp != context->Sp + 0x3b0
      || unwound.Pc != saved[3])
    ExitProcess (43);

  ExitProcess (0);
}
