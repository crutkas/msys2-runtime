/* External AArch64 definitions for the fenv trap-control extensions.

   Newlib implements these functions as static inline FPCR operations.  The
   runtime exports require external definitions with the same semantics. */

#define feenableexcept __cygwin_inline_feenableexcept
#define fedisableexcept __cygwin_inline_fedisableexcept
#define fegetexcept __cygwin_inline_fegetexcept
#include <fenv.h>
#undef feenableexcept
#undef fedisableexcept
#undef fegetexcept

int
feenableexcept (int mask)
{
  return __cygwin_inline_feenableexcept (mask);
}

int
fedisableexcept (int mask)
{
  return __cygwin_inline_fedisableexcept (mask);
}

int
fegetexcept (void)
{
  return __cygwin_inline_fegetexcept ();
}
