/* Cygwin AArch64 binary64 long double regression.

   Build with the target compiler and the completed runtime:
     msys2-gcc -O2 -fno-builtin math-arm64.c -lm -o math-arm64.exe
   Run math-arm64.exe on Windows on Arm.  Cross-compiling alone does not test
   the floating-point results or the native floating-point environment.

   This file is part of Cygwin.

   This software is a copyrighted work licensed under the terms of the
   Cygwin license.  Please consult the file "CYGWIN_LICENSE" for details. */

#include <assert.h>
#include <complex.h>
#include <fenv.h>
#include <float.h>
#include <limits.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

_Static_assert (sizeof (long) == 8 && sizeof (void *) == 8,
		"Cygwin AArch64 is LP64");
_Static_assert (sizeof (long double) == 8 && sizeof (double) == 8
		&& LDBL_MANT_DIG == 53 && DBL_MANT_DIG == 53
		&& LDBL_MIN_EXP == DBL_MIN_EXP
		&& LDBL_MAX_EXP == DBL_MAX_EXP,
		"Cygwin AArch64 uses binary64 long double");

/* Cygwin extensions not declared in the default feature-test configuration.
   Use the exported trap-control functions, not newlib's static inlines. */
extern long double exp10l (long double);
extern long double pow10l (long double);
extern long double lgammal_r (long double, int *);
extern long double scalbl (long double, long double);
extern void sincosl (long double, long double *, long double *);
extern long double complex clog10l (long double complex);
extern int external_fegetexcept (void) __asm__ ("fegetexcept");
extern int external_fedisableexcept (int) __asm__ ("fedisableexcept");
extern int external_feenableexcept (int) __asm__ ("feenableexcept");

static uint64_t
bits (long double x)
{
  uint64_t result;
  memcpy (&result, &x, sizeof result);
  return result;
}

static void
check_unary (void)
{
  static const struct
  {
    long double (*wide) (long double);
    double (*narrow) (double);
    double argument;
  } cases[] =
  {
#define CASE(name, x) { name##l, name, x }
    CASE (acos, 0.25), CASE (acosh, 1.25), CASE (asin, 0.25),
    CASE (asinh, 0.25), CASE (atan, 0.25), CASE (atanh, 0.25),
    CASE (cbrt, 0.25), CASE (ceil, 0.25), CASE (cos, 0.25),
    CASE (cosh, 0.25), CASE (erf, 1.0), CASE (erfc, 1.0),
    CASE (exp, 0.25), CASE (exp2, 0.25), CASE (expm1, 0.25),
    CASE (fabs, -0.25), CASE (floor, -0.25), CASE (lgamma, 0.25),
    CASE (log, 0.25), CASE (log10, 0.25), CASE (log1p, 0.25),
    CASE (log2, 0.25), CASE (logb, 0.25), CASE (nearbyint, 0.25),
    CASE (rint, 0.25), CASE (round, 0.25), CASE (sin, 0.25),
    CASE (sinh, 0.25), CASE (sqrt, 0.25), CASE (tan, 0.25),
    CASE (tanh, 0.25), CASE (tgamma, 0.25), CASE (trunc, -0.25)
#undef CASE
  };

  for (unsigned int i = 0; i < sizeof cases / sizeof cases[0]; ++i)
    assert (bits (cases[i].wide (cases[i].argument))
	    == bits (cases[i].narrow (cases[i].argument)));

  assert (fabsl (erfl (1.0L) - 0.8427007929497149L) < 0x1p-51L);
  assert (fabsl (erfcl (1.0L) - 0.1572992070502851L) < 0x1p-53L);
  assert (fabsl (tgammal (5.0L) - 24.0L) < 0x1p-45L);
  assert (fabsl (lgammal (5.0L) - logl (24.0L)) < 0x1p-49L);
}

static void
check_binary (void)
{
  static const struct
  {
    long double (*wide) (long double, long double);
    double (*narrow) (double, double);
  } cases[] =
  {
#define CASE(name) { name##l, name }
    CASE (atan2), CASE (copysign), CASE (fdim), CASE (fmax), CASE (fmin),
    CASE (fmod), CASE (hypot), CASE (nextafter), CASE (pow), CASE (remainder)
#undef CASE
  };

  for (unsigned int i = 0; i < sizeof cases / sizeof cases[0]; ++i)
    assert (bits (cases[i].wide (2.75L, 1.5L))
	    == bits (cases[i].narrow (2.75, 1.5)));

  assert (bits (nextafterl (1.0L, 2.0L)) == UINT64_C (0x3ff0000000000001));
  assert (bits (nextafterl (1.0L, 0.0L)) == UINT64_C (0x3fefffffffffffff));
  assert (bits (nextafterl (0.0L, -0.0L)) == UINT64_C (0x8000000000000000));
  assert (bits (nextafterl (0.0L, 1.0L)) == 1);
  assert (bits (nextafterl (0.0L, -1.0L)) == UINT64_C (0x8000000000000001));
  assert (bits (nextafterl (LDBL_MIN, 0.0L)) == UINT64_C (0x000fffffffffffff));
  assert (isinf (nextafterl (LDBL_MAX, INFINITY)));
  assert (isnan (nextafterl (NAN, 0.0L)));
  assert (bits (nexttowardl (1.0L, 2.0L)) == bits (nextafterl (1.0L, 2.0L)));
  assert (nexttoward (1.0, 2.0L) == nextafter (1.0, 2.0));
  assert (nexttowardf (1.0f, 1.0L + 0x1p-30L) == nextafterf (1.0f, 2.0f));
  assert (nexttowardf (1.0f, 1.0L - 0x1p-30L) == nextafterf (1.0f, 0.0f));
  assert (fmal (0x1.0000002p0L, 0x1.ffffffcp-1L, -1.0L) == -0x1p-54L);
}

static void
check_rounding (void)
{
  int round = fegetround ();
  int traps = external_fedisableexcept (FE_ALL_EXCEPT);
  assert (traps >= 0);
  assert (external_fegetexcept () == 0);
  assert (external_feenableexcept (0) == 0);

  assert (fesetround (FE_UPWARD) == 0);
  assert (lrintl (0x1p40L + 0.25L) == (1L << 40) + 1);
  assert (llrintl (0x1p40L + 0.25L) == (1LL << 40) + 1);
  assert (rintl (2.25L) == 3.0L);
  assert (fesetround (FE_DOWNWARD) == 0);
  assert (lrintl (0x1p40L + 0.75L) == (1L << 40));
  assert (rintl (-2.25L) == -3.0L);
  assert (lroundl (0x1p40L + 0.75L) == (1L << 40) + 1);
  assert (llroundl (-2.5L) == -3);
  assert (feclearexcept (FE_ALL_EXCEPT) == 0);
  assert (nearbyintl (2.25L) == 2.0L);
  assert ((fetestexcept (FE_INEXACT) & FE_INEXACT) == 0);
  assert (rintl (2.25L) == 2.0L);
  assert ((fetestexcept (FE_INEXACT) & FE_INEXACT) != 0);
  assert (fesetround (round) == 0);
  assert (feclearexcept (FE_ALL_EXCEPT) == 0);
  assert (external_feenableexcept (traps) >= 0);
}

static void
check_extensions (void)
{
  int exponent, quotient, sign;
  long double integer, s, c;
  int oldsign = signgam;
  signgam = 7;
  assert (fabsl (lgammal_r (-0.5L, &sign) - logl (2.0L * sqrtl (acosl (-1.0L))))
	  < 0x1p-49L);
  assert (sign == -1 && signgam == 7);
  signgam = oldsign;
  assert (frexpl (12.0L, &exponent) == 0.75L && exponent == 4);
  assert (ldexpl (0.75L, 4) == 12.0L);
  assert (ilogbl (12.0L) == 3);
  assert (modfl (-1.25L, &integer) == -0.25L && integer == -1.0L);
  assert (remquol (5.0L, 2.0L, &quotient) == 1.0L && (quotient & 7) == 2);
  assert (scalbnl (1.0L, 8) == 256.0L);
  assert (scalblnl (1.0L, LONG_MAX) == INFINITY);
  assert (scalblnl (1.0L, LONG_MIN) == 0.0L);
  assert (scalbl (1.0L, 8.0L) == 256.0L);
  assert (isnan (scalbl (1.0L, 0.5L)));
  assert (isnan (scalbl (0.0L, INFINITY)));
  assert (scalbl (1.0L, INFINITY) == INFINITY);
  assert (scalbl (1.0L, -INFINITY) == 0.0L);
  assert (scalbl (1.0L, 0x1p40L) == INFINITY);
  assert (scalbl (1.0L, -0x1p40L) == 0.0L);
  assert (exp10l (2.0L) == 100.0L && pow10l (2.0L) == 100.0L);
  sincosl (-0.0L, &s, &c);
  assert (bits (s) == bits (-0.0L) && c == 1.0L);
  sincosl (0.25L, &s, &c);
  assert (s == sinl (0.25L) && c == cosl (0.25L));
}

static void
check_complex (void)
{
  long double complex z;
  __real__ z = -4.0L;
  __imag__ z = -0.0L;
  z = csqrtl (z);
  assert (creall (z) == 0.0L && cimagl (z) == -2.0L);
  __real__ z = 3.0L;
  __imag__ z = 4.0L;
  assert (cabsl (z) == 5.0L);
  assert (cimagl (conjl (z)) == -4.0L);
  __real__ z = 100.0L;
  __imag__ z = 0.0L;
  z = clog10l (z);
  assert (creall (z) == 2.0L && cimagl (z) == 0.0L);
}

int
main (void)
{
  check_unary ();
  check_binary ();
  check_rounding ();
  check_extensions ();
  check_complex ();
  puts ("Cygwin AArch64 binary64 math regression passed");
  return 0;
}
