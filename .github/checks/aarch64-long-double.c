#include <float.h>
#include <math.h>

#ifndef __aarch64__
#error "Expected an AArch64 compiler target"
#endif

#ifndef __CYGWIN__
#error "Expected a Cygwin compiler target"
#endif

_Static_assert(sizeof(double) == 8, "Windows ARM64 double must be 64-bit");
_Static_assert(sizeof(long double) == 8,
	       "Windows ARM64 long double must be 64-bit");
_Static_assert(_Alignof(long double) == 8,
	       "Windows ARM64 long double must be 8-byte aligned");
_Static_assert(LDBL_MANT_DIG == 53,
	       "Windows ARM64 long double must use IEEE binary64 precision");
_Static_assert(LDBL_MAX_EXP == 1024,
	       "Windows ARM64 long double must use IEEE binary64 exponent range");
_Static_assert(LDBL_MANT_DIG == DBL_MANT_DIG,
	       "Windows ARM64 long double and double precision must match");
_Static_assert(LDBL_MAX_EXP == DBL_MAX_EXP,
	       "Windows ARM64 long double and double exponent range must match");

unsigned char long_double_size[sizeof(long double)];
unsigned char long_double_alignment[_Alignof(long double)];

long double
check_long_double_math (long double x, long double y, int *exp)
{
  return acoshl (x) + acosl (x) + asinhl (x) + asinl (x)
	 + atan2l (x, y) + atanhl (x) + atanl (x) + cbrtl (x)
	 + coshl (x) + cosl (x) + expl (x) + fmodl (x, y)
	 + frexpl (x, exp) + logl (x) + remainderl (x, y)
	 + scalbnl (x, *exp) + sinhl (x) + sinl (x) + sqrtl (x)
	 + tanhl (x) + tanl (x);
}
