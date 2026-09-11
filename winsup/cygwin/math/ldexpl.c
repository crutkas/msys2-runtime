/**
 * This file has no copyright assigned and is placed in the Public Domain.
 * This file is part of the mingw-w64 runtime package.
 * No warranty is given; refer to the file DISCLAIMER.PD within this package.
 */
#include <math.h>
#include <errno.h>

long double ldexpl(long double x, int expn)
{
  long double res = 0.0L;
  if (!isfinite (x) || x == 0.0L)
    return x;

#ifdef __x86_64__
  __asm__ __volatile__ ("fscale"
	    : "=t" (res)
	    : "0" (x), "u" ((long double) expn));
#else
  /* AArch64 has no x87 fscale; long double is the same 64-bit IEEE double
     as double here, so delegate to the double-precision ldexp. */
  res = __builtin_ldexp ((double) x, expn);
#endif

  if (!isfinite (res) || res == 0.0L)
    errno = ERANGE;

  return res;
}
