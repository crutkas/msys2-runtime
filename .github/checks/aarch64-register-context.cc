#include <stddef.h>
#include <stdint.h>
#include <sys/types.h>
#include <sys/select.h>
#include <sys/_pthreadtypes.h>
#include <time.h>
#include <windows.h>
#include <cygwin/signal.h>
#include "register.h"

#if !defined(__aarch64__)
#error This check must be compiled for AArch64
#endif

#define CHECK_CONTEXT_OFFSET(cygwin_name, windows_name) \
  static_assert (offsetof (__mcontext, cygwin_name) \
		 == offsetof (CONTEXT, windows_name))

CHECK_CONTEXT_OFFSET (ctxflags, ContextFlags);
CHECK_CONTEXT_OFFSET (cpsr, Cpsr);
CHECK_CONTEXT_OFFSET (x0, X0);
CHECK_CONTEXT_OFFSET (x19, X19);
CHECK_CONTEXT_OFFSET (fp, Fp);
CHECK_CONTEXT_OFFSET (lr, Lr);
CHECK_CONTEXT_OFFSET (sp, Sp);
CHECK_CONTEXT_OFFSET (pc, Pc);
CHECK_CONTEXT_OFFSET (v, V);
CHECK_CONTEXT_OFFSET (fpcr, Fpcr);
CHECK_CONTEXT_OFFSET (fpsr, Fpsr);
CHECK_CONTEXT_OFFSET (bcr, Bcr);
CHECK_CONTEXT_OFFSET (bvr, Bvr);
CHECK_CONTEXT_OFFSET (wcr, Wcr);
CHECK_CONTEXT_OFFSET (wvr, Wvr);

static_assert (alignof (__mcontext) == alignof (CONTEXT));
static_assert (offsetof (__mcontext, oldmask) == sizeof (CONTEXT));
static_assert (sizeof (__mcontext) == sizeof (CONTEXT) + 16);

void
check_register_aliases (CONTEXT &context, __mcontext &mcontext)
{
  context._CX_instPtr = mcontext._MC_instPtr;
  context._CX_stackPtr = mcontext._MC_stackPtr;
  context._CX_framePtr = mcontext._MC_uclinkReg;
  mcontext._MC_retReg = context._CX_instPtr;
}
