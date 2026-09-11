/**
 * This file has no copyright assigned and is placed in the Public Domain.
 * This file is part of the mingw-w64 runtime package.
 * No warranty is given; refer to the file DISCLAIMER.PD within this package.
 */
/*
 * Written by J.T. Conklin <jtc@netbsd.org>.
 * Public domain.
 * Adapted for long double type by Danny Smith <dannysmith@users.sourceforge.net>.
 */

/* asin = atan (x / sqrt(1 - x^2)) */
long double asinl (long double x);

long double asinl (long double x)
{
#ifdef __x86_64__
  long double res = 0.0L;

  asm volatile (
	"fld	%%st\n\t"
	"fmul	%%st(0)\n\t"			/* x^2 */
	"fld1\n\t"
	"fsubp\n\t"				/* 1 - x^2 */
	"fsqrt\n\t"				/* sqrt (1 - x^2) */
	"fpatan"
	: "=t" (res) : "0" (x) : "st(1)");
  return res;
#else
  /* AArch64 has no x87.  long double is the same 64-bit IEEE double as
     double here, so delegate to the double-precision asin, which comes
     from newlib and therefore does not recurse. */
  return __builtin_asin ((double) x);
#endif
}
