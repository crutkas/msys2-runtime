/* External definitions for the AArch64 fenv trap-control functions.
 *
 * newlib's libc/machine/aarch64/sys/fenv.h ALREADY implements
 * feenableexcept / fedisableexcept / fegetexcept with the correct FPCR idiom
 * (mrs/msr fpcr), but declares them `static inline` under __BSD_VISIBLE and
 * states in a comment: "We currently provide no external definitions of the
 * functions below."  cygwin.din exports them, so the DLL needs real symbols.
 *
 * Rather than DUPLICATE newlib's implementation (which collides with it), this
 * emits external definitions that CALL newlib's own inline versions, via an
 * asm label so the C identifier does not clash with the inline one.
 *
 * CAVEAT, carried deliberately and not fixed here: the FPCR trap-enable bits
 * are RAZ/WI (read-as-zero, write-ignored) on many AArch64 implementations,
 * including Windows on Arm.  These functions therefore may not actually enable
 * hardware FP traps.  That is a property of the architecture and the platform,
 * not of this code, and it is equally true of newlib's inline versions.
 * UNEXECUTED AND UNVALIDATED: no part of this has been run.
 */

#include <fenv.h>

extern int __cygwin_feenableexcept (int) __asm__ ("feenableexcept");
extern int __cygwin_fedisableexcept (int) __asm__ ("fedisableexcept");
extern int __cygwin_fegetexcept (void) __asm__ ("fegetexcept");

int
__cygwin_feenableexcept (int mask)
{
  return feenableexcept (mask);
}

int
__cygwin_fedisableexcept (int mask)
{
  return fedisableexcept (mask);
}

int
__cygwin_fegetexcept (void)
{
  return fegetexcept ();
}
