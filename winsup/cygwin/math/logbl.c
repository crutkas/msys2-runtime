/**
 * This file has no copyright assigned and is placed in the Public Domain.
 * This file is part of the mingw-w64 runtime package.
 * No warranty is given; refer to the file DISCLAIMER.PD within this package.
 */
/*
 * Written by J.T. Conklin <jtc@netbsd.org>.
 * Changes for long double by Ulrich Drepper <drepper@cygnus.com>
 * Public domain.
 */

#include <math.h>

long double
logbl (long double x)
{
#ifdef __x86_64__
  long double res = 0.0L;

  asm volatile (
       "fxtract\n\t"
       "fstp	%%st" : "=t" (res) : "0" (x));
  return res;
#else
  /* AArch64 has no x87 fxtract; long double is the same 64-bit IEEE
     double as double here, so delegate to the double-precision logb. */
  return __builtin_logb ((double) x);
#endif
}
