/* math/aarch64/longdouble.c: long double routines for AArch64.

This file is part of Cygwin.

This software is a copyrighted work licensed under the terms of the
Cygwin license.  Please consult the file "CYGWIN_LICENSE" for
details. */

/* The Cygwin AArch64 ABI uses binary64 long double, unlike AArch64 SysV.
   Newlib's _LDBL_EQ_DBL implementations supply the standard real and complex
   math functions.  Define only the additional Cygwin exports here: selecting
   the x87 C sources as well would override newlib with 80-bit layouts and
   coefficients, not merely lose precision. */

#include <float.h>
#include <math.h>

#ifndef _LDBL_EQ_DBL
#error "Cygwin AArch64 math requires newlib's binary64 long double implementations"
#endif

_Static_assert (sizeof (long double) == 8 && sizeof (double) == 8
		&& FLT_RADIX == 2 && LDBL_MANT_DIG == 53 && DBL_MANT_DIG == 53
		&& LDBL_MIN_EXP == DBL_MIN_EXP
		&& LDBL_MAX_EXP == DBL_MAX_EXP,
		"Cygwin AArch64 requires binary64 long double and double");

/* These double extensions are hidden by some feature-test configurations. */
extern double scalb (double, double);
extern void sincos (double, double *, double *);

long double
scalbl (long double x, long double n)
{
  /* Do not convert n to int: scalb also handles fractional, infinite and
     out-of-range exponents, including their floating-point exceptions. */
  return scalb (x, n);
}

long double
lgammal_r (long double x, int *signp)
{
  return lgamma_r (x, signp);
}

void
sincosl (long double x, long double *sinp, long double *cosp)
{
  double s, c;
  sincos (x, &s, &c);
  /* Equal representations do not make double * and long double * alias. */
  *sinp = s;
  *cosp = c;
}

int
isinfl (long double x)
{
  return __builtin_isinf_sign (x);
}

int
isnanl (long double x)
{
  return __builtin_isnan (x);
}

/* Retained for compatibility with the historical data export in isinf.c. */
const double __infinity[1] = { __builtin_huge_val () };
