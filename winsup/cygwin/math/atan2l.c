/**
 * This file has no copyright assigned and is placed in the Public Domain.
 * This file is part of the mingw-w64 runtime package.
 * No warranty is given; refer to the file DISCLAIMER.PD within this package.
 */
long double atan2l (long double y, long double x);

long double
atan2l (long double y, long double x)
{
#ifdef __x86_64__
  long double res = 0.0L;
  asm volatile ("fpatan" : "=t" (res) : "u" (y), "0" (x) : "st(1)");
  return res;
#else
  /* AArch64 has no x87 fpatan.  long double is the same 64-bit IEEE
     double as double here, so delegate to the double-precision atan2,
     which comes from newlib and therefore does not recurse. */
  return __builtin_atan2 ((double) y, (double) x);
#endif
}
