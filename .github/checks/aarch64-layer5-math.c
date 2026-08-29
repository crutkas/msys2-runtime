#define _GNU_SOURCE
#define _WIN32_WINNT 0x0a00

#include <errno.h>
#include <float.h>
#include <math.h>
#include <stdio.h>
#include <windows.h>

extern long double __cosl_internal (long double);
extern long double __sinl_internal (long double);
extern long double scalbl (long double, long double);
extern long double scalblnl (long double, long);

static int failures;

static void
fail (const char *name, long double actual, long double expected)
{
  fprintf (stderr, "%s: actual=%.21Lg expected=%.21Lg errno=%d\n",
	   name, actual, expected, errno);
  ++failures;
}

static void
check_close (const char *name, long double actual, double expected,
	     double tolerance)
{
  double converted = (double) actual;
  double difference;
  double scale;

  if (isnan (expected))
    {
      if (!isnan (converted))
	fail (name, actual, expected);
      return;
    }
  if (isinf (expected))
    {
      if (!isinf (converted) || signbit (converted) != signbit (expected))
	fail (name, actual, expected);
      return;
    }
  difference = fabs (converted - expected);
  scale = fmax (1.0, fabs (expected));
  if (difference > tolerance * scale)
    fail (name, actual, expected);
}

static void
check_exact (const char *name, long double actual, double expected)
{
  if ((double) actual != expected
      || (expected == 0.0 && signbit ((double) actual) != signbit (expected)))
    fail (name, actual, expected);
}

static void
check_native_process (void)
{
  USHORT process_machine;
  USHORT native_machine;

  if (!IsWow64Process2 (GetCurrentProcess (), &process_machine,
			&native_machine)
      || native_machine != IMAGE_FILE_MACHINE_ARM64
      || process_machine != IMAGE_FILE_MACHINE_UNKNOWN)
    {
      fprintf (stderr,
	       "process architecture mismatch: process=0x%04x native=0x%04x\n",
	       process_machine, native_machine);
      ++failures;
    }
}

int
main (void)
{
  long double (*volatile p_acosl) (long double) = acosl;
  long double (*volatile p_acoshl) (long double) = acoshl;
  long double (*volatile p_asinhl) (long double) = asinhl;
  long double (*volatile p_atanhl) (long double) = atanhl;
  long double (*volatile p_exp2l) (long double) = exp2l;
  long double (*volatile p_expm1l) (long double) = expm1l;
  long double (*volatile p_frexpl) (long double, int *) = frexpl;
  int (*volatile p_ilogbl) (long double) = ilogbl;
  long double (*volatile p_log10l) (long double) = log10l;
  long double (*volatile p_log1pl) (long double) = log1pl;
  long double (*volatile p_log2l) (long double) = log2l;
  long double (*volatile p_remainderl) (long double, long double) = remainderl;
  long double (*volatile p_remquol) (long double, long double, int *) = remquol;
  long double (*volatile p_scalbl) (long double, long double) = scalbl;
  long double (*volatile p_scalbnl) (long double, int) = scalbnl;
  long double (*volatile p_scalblnl) (long double, long) = scalblnl;
  long double (*volatile p_tanl) (long double) = tanl;
  const double tolerance = 16.0 * DBL_EPSILON;
  volatile long double zero = 0.0L;
  long double infinity = 1.0L / zero;
  int exponent;
  int quotient;
  int reference_quotient;

  _Static_assert (sizeof (long double) == sizeof (double),
		  "Windows ARM64 long double must use the double ABI");
  check_native_process ();

  check_close ("acosl normal", p_acosl (0.5L), acos (0.5), tolerance);
  check_close ("acosl negative quadrant", p_acosl (-0.5L), acos (-0.5),
	       tolerance);
  check_exact ("acosl +1", p_acosl (1.0L), 0.0);
  check_close ("acosl -1", p_acosl (-1.0L), acos (-1.0), tolerance);
  check_close ("acosl NaN", p_acosl (NAN), NAN, tolerance);
  errno = 0;
  check_close ("acosl domain", p_acosl (2.0L), NAN, tolerance);
  if (errno != EDOM)
    {
      fprintf (stderr, "acosl domain did not set EDOM: %d\n", errno);
      ++failures;
    }
  check_close ("acoshl", p_acoshl (2.0L), acosh (2.0), tolerance);
  check_close ("asinhl", p_asinhl (-2.0L), asinh (-2.0), tolerance);
  check_close ("atanhl", p_atanhl (0.5L), atanh (0.5), tolerance);

  check_close ("expm1l tiny+", p_expm1l (0x1p-52L), expm1 (0x1p-52),
	       tolerance);
  check_close ("expm1l tiny-", p_expm1l (-0x1p-52L), expm1 (-0x1p-52),
	       tolerance);
  check_close ("expm1l normal", p_expm1l (0.5L), expm1 (0.5), tolerance);
  check_exact ("expm1l -Inf", p_expm1l (-infinity), -1.0);
  check_close ("expm1l +Inf", p_expm1l (infinity), (double) infinity,
	       tolerance);
  errno = 0;
  check_close ("expm1l NaN", p_expm1l (NAN), NAN, tolerance);
  if (errno != EDOM)
    {
      fprintf (stderr, "expm1l NaN did not set EDOM: %d\n", errno);
      ++failures;
    }

  check_close ("exp2l", p_exp2l (-4.5L), exp2 (-4.5), tolerance);
  check_close ("log10l", p_log10l (1000.0L), log10 (1000.0), tolerance);
  check_close ("log1pl boundary", p_log1pl (-0.5L), log1p (-0.5),
	       tolerance);
  check_close ("log2l", p_log2l (0.125L), log2 (0.125), tolerance);
  check_close ("tanl quadrant", p_tanl (-2.0L), tan (-2.0), tolerance);
  check_close ("sinl internal", __sinl_internal (2.0L), sin (2.0),
	       tolerance);
  check_close ("cosl internal", __cosl_internal (2.0L), cos (2.0),
	       tolerance);

  exponent = 0;
  check_close ("frexpl", p_frexpl (-10.0L, &exponent), -0.625, tolerance);
  if (exponent != 4)
    {
      fprintf (stderr, "frexpl exponent: actual=%d expected=4\n", exponent);
      ++failures;
    }
  if (p_ilogbl (0.125L) != ilogb (0.125))
    {
      fprintf (stderr, "ilogbl finite result mismatch\n");
      ++failures;
    }

  check_close ("remainderl", p_remainderl (7.0L, 2.0L),
	       remainder (7.0, 2.0), tolerance);
  quotient = reference_quotient = 0;
  check_close ("remquol", p_remquol (-7.0L, 2.0L, &quotient),
	       remquo (-7.0, 2.0, &reference_quotient), tolerance);
  if ((quotient & 7) != (reference_quotient & 7))
    {
      fprintf (stderr, "remquol quotient mismatch: %d != %d\n",
	       quotient, reference_quotient);
      ++failures;
    }

  check_exact ("scalbnl normal", p_scalbnl (0.75L, 10),
	       scalbn (0.75, 10));
  check_exact ("scalbnl upper boundary", p_scalbnl (0.5L, 1024),
	       scalbn (0.5, 1024));
  check_exact ("scalbnl subnormal", p_scalbnl (DBL_MIN, -1),
	       scalbn (DBL_MIN, -1));
  errno = 0;
  check_close ("scalbnl product overflow", p_scalbnl (DBL_MAX, 1),
	       INFINITY, tolerance);
  if (errno != ERANGE)
    {
      fprintf (stderr, "scalbnl product overflow did not set ERANGE: %d\n",
	       errno);
      ++failures;
    }
  errno = 0;
  check_close ("scalbnl overflow", p_scalbnl (1.0L, 1024), INFINITY,
	       tolerance);
  if (errno != ERANGE)
    {
      fprintf (stderr, "scalbnl overflow did not set ERANGE: %d\n", errno);
      ++failures;
    }
  check_exact ("scalblnl", p_scalblnl (0.75L, -10),
	       scalbln (0.75, -10));
  check_close ("scalbl", p_scalbl (0.75L, 5.0), scalbn (0.75, 5),
	       tolerance);
  check_close ("scalbl fractional exponent", p_scalbl (2.0L, 0.5L),
	       NAN, tolerance);
  check_close ("scalbl NaN exponent", p_scalbl (2.0L, NAN), NAN,
	       tolerance);
  check_close ("scalbl +Inf exponent", p_scalbl (2.0L, infinity),
	       INFINITY, tolerance);
  check_close ("scalbl zero by +Inf", p_scalbl (0.0L, infinity), NAN,
	       tolerance);
  check_exact ("scalbl -Inf exponent", p_scalbl (2.0L, -infinity), 0.0);

  if (failures)
    return 1;
  puts ("Native ARM64 production math checks passed.");
  return 0;
}
