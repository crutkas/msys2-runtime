/**
 * This file has no copyright assigned and is placed in the Public Domain.
 * This file is part of the mingw-w64 runtime package.
 * No warranty is given; refer to the file DISCLAIMER.PD within this package.
 */

void sincos (double __x, double *p_sin, double *p_cos);
void sincosl (long double __x, long double *p_sin, long double *p_cos);
void sincosf (float __x, float *p_sin, float *p_cos);

void sincos (double __x, double *p_sin, double *p_cos)
{
#ifdef __x86_64__
  long double c, s;

  __asm__ __volatile__ ("fsincos\n\t"
    "fnstsw    %%ax\n\t"
    "testl     $0x400, %%eax\n\t"
    "jz        1f\n\t"
    "fldpi\n\t"
    "fadd      %%st(0)\n\t"
    "fxch      %%st(1)\n\t"
    "2: fprem1\n\t"
    "fnstsw    %%ax\n\t"
    "testl     $0x400, %%eax\n\t"
    "jnz       2b\n\t"
    "fstp      %%st(1)\n\t"
    "fsincos\n\t"
    "1:" : "=t" (c), "=u" (s) : "0" (__x));
  *p_sin = (double) s;
  *p_cos = (double) c;
#else
  /* AArch64 has no x87 fsincos, so compute the two values separately.
     sin and cos come from newlib, so this does not recurse. */
  *p_sin = __builtin_sin (__x);
  *p_cos = __builtin_cos (__x);
#endif
}

void sincosf (float __x, float *p_sin, float *p_cos)
{
#ifdef __x86_64__
  long double c, s;

  __asm__ __volatile__ ("fsincos\n\t"
    "fnstsw    %%ax\n\t"
    "testl     $0x400, %%eax\n\t"
    "jz        1f\n\t"
    "fldpi\n\t"
    "fadd      %%st(0)\n\t"
    "fxch      %%st(1)\n\t"
    "2: fprem1\n\t"
    "fnstsw    %%ax\n\t"
    "testl     $0x400, %%eax\n\t"
    "jnz       2b\n\t"
    "fstp      %%st(1)\n\t"
    "fsincos\n\t"
    "1:" : "=t" (c), "=u" (s) : "0" (__x));
  *p_sin = (float) s;
  *p_cos = (float) c;
#else
  /* AArch64 has no x87 fsincos, so compute the two values separately.
     sin and cos come from newlib, so this does not recurse. */
  *p_sin = __builtin_sinf (__x);
  *p_cos = __builtin_cosf (__x);
#endif
}

void sincosl (long double __x, long double *p_sin, long double *p_cos)
{
#ifdef __x86_64__
  long double c, s;

  __asm__ __volatile__ ("fsincos\n\t"
    "fnstsw    %%ax\n\t"
    "testl     $0x400, %%eax\n\t"
    "jz        1f\n\t"
    "fldpi\n\t"
    "fadd      %%st(0)\n\t"
    "fxch      %%st(1)\n\t"
    "2: fprem1\n\t"
    "fnstsw    %%ax\n\t"
    "testl     $0x400, %%eax\n\t"
    "jnz       2b\n\t"
    "fstp      %%st(1)\n\t"
    "fsincos\n\t"
    "1:" : "=t" (c), "=u" (s) : "0" (__x));
  *p_sin = s;
  *p_cos = c;
#else
  /* AArch64 has no x87 fsincos, so compute the two values separately.
     sin and cos come from newlib, so this does not recurse. */
  *p_sin = __builtin_sin ((double) __x);
  *p_cos = __builtin_cos ((double) __x);
#endif
}
