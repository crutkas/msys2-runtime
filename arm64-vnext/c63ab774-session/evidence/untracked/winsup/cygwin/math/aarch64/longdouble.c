/* math/aarch64/longdouble.c: long double routines for AArch64.

This file is part of Cygwin.

This software is a copyrighted work licensed under the terms of the
Cygwin license.  Please consult the file "CYGWIN_LICENSE" for
details. */

/* On x86_64 the routines below are supplied by hand-written x87 assembly
   (the math/ *.S files), which operates on the 80-bit extended precision
   format.  AArch64 has no x87 and no 80-bit type: here long double is
   simply the same 64-bit IEEE double as double.  Each routine therefore
   delegates to its double-precision counterpart, which is an exact
   implementation rather than an approximation.

   The static assertion below makes that assumption fail loudly at compile
   time should a future AArch64 target use a wider long double (for
   example the 128-bit quad format used by the AArch64 SysV ABI).

   Note that the double and float variants of nearbyint and remainder,
   which the x87 assembly also provided, are deliberately NOT defined
   here: newlib supplies those, and the assembly merely overrode them.
   Defining them again would be a duplicate symbol, and delegating them
   to themselves would recurse. */

#include <math.h>

_Static_assert (sizeof (long double) == sizeof (double),
		"AArch64 long double is expected to be the same 64-bit IEEE "
		"double as double; the delegations below are only valid then");

long double
ceill (long double x)
{
  return ceil ((double) x);
}

long double
copysignl (long double x, long double y)
{
  return copysign ((double) x, (double) y);
}

long double
exp2l (long double x)
{
  return exp2 ((double) x);
}

long double
floorl (long double x)
{
  return floor ((double) x);
}

long double
frexpl (long double x, int *expptr)
{
  return frexp ((double) x, expptr);
}

int
ilogbl (long double x)
{
  return ilogb ((double) x);
}

long double
log10l (long double x)
{
  return log10 ((double) x);
}

long double
log1pl (long double x)
{
  return log1p ((double) x);
}

long double
log2l (long double x)
{
  return log2 ((double) x);
}

long double
nearbyintl (long double x)
{
  return nearbyint ((double) x);
}

long double
remainderl (long double x, long double y)
{
  return remainder ((double) x, (double) y);
}

long double
remquol (long double x, long double y, int *quo)
{
  return remquo ((double) x, (double) y, quo);
}

long double
scalbl (long double x, long double n)
{
  /* scalb (x, n) is x * 2^n for integral n, which is exactly what
     scalbn computes.  scalb itself is a legacy interface that this
     target's <math.h> does not declare. */
  return scalbn ((double) x, (int) n);
}

long double
scalbnl (long double x, int n)
{
  return scalbn ((double) x, n);
}

long double
scalblnl (long double x, long n)
{
  return scalbln ((double) x, n);
}

long double
tanl (long double x)
{
  return tan ((double) x);
}

/* Internal helpers used by cos.def.h, sin.def.h and log.def.h.  These are
   only ever called from the long double instantiations (cosl, sinl, logl);
   the double entry points cos, sin and log come from newlib and are not
   built from those .def.h files, so delegating here does not recurse. */

long double
__cosl_internal (long double x)
{
  return cos ((double) x);
}

long double
__sinl_internal (long double x)
{
  return sin ((double) x);
}

long double
__logl_internal (long double x)
{
  return log ((double) x);
}
