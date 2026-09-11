/* AArch64 GCC passes the profiled function's caller PC as its argument. */
#include <stdint.h>

extern void _mcount_private (uintptr_t, uintptr_t);

void __attribute__ ((no_instrument_function))
_mcount (uintptr_t frompc)
{
  _mcount_private (frompc, (uintptr_t) __builtin_return_address (0));
}
