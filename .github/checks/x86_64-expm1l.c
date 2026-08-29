#define _GNU_SOURCE

#include <errno.h>
#include <fenv.h>
#include <float.h>
#include <math.h>
#include <stdio.h>

static long double
small_reference (long double x)
{
  long double term = x;
  long double sum = x;

  for (int divisor = 2; divisor < 40; ++divisor)
    {
      term *= x / divisor;
      sum += term;
    }
  return sum;
}

static int
check_small (const char *name, long double x)
{
  long double (*volatile production) (long double) = expm1l;
  long double actual = production (x);
  long double expected = small_reference (x);
  long double difference = fabsl (actual - expected);
  long double tolerance;

  if (fabsl (x) < 0x1p-32L)
    tolerance = LDBL_EPSILON * fabsl (expected);
  else
    tolerance = 4.0L * DBL_EPSILON * fabsl (expected);

  if (difference <= tolerance)
    return 0;
  fprintf (stderr, "%s: actual=%.21Lg expected=%.21Lg\n",
	   name, actual, expected);
  return 1;
}

int
main (void)
{
#ifndef __x86_64__
#error this regression verifies the x86_64 f2xm1 production path
#endif
  long double (*volatile production) (long double) = expm1l;
  long double result;
  int failures = 0;

  failures += check_small ("tiny positive", 0x1p-60L);
  failures += check_small ("tiny negative", -0x1p-60L);
  failures += check_small ("round-to-input positive", 0x1p-65L);
  failures += check_small ("round-to-input negative", -0x1p-65L);
  failures += check_small ("Taylor threshold positive", 0x1p-40L);
  failures += check_small ("Taylor threshold negative", -0x1p-40L);
  failures += check_small ("small positive", 0.125L);
  failures += check_small ("small negative", -0.125L);
  result = production (-INFINITY);
  if (result != -1.0L)
    {
      fprintf (stderr, "-Inf handling failed: %.21Lg\n", result);
      ++failures;
    }
  feclearexcept (FE_ALL_EXCEPT);
  result = production (LDBL_MIN);
  if (result != LDBL_MIN || fetestexcept (FE_UNDERFLOW))
    {
      fprintf (stderr, "tiny normal raised underflow: %.21Lg flags=%d\n",
	       result, fetestexcept (FE_ALL_EXCEPT));
      ++failures;
    }
  errno = 0;
  if (!isnan (production (NAN)) || errno != EDOM)
    {
      fprintf (stderr, "NaN handling failed: errno=%d\n", errno);
      ++failures;
    }
  if (failures)
    return 1;
  puts ("x86_64 production expm1l regression passed.");
  return 0;
}
