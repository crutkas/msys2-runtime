#include <stdint.h>

#if !defined(__aarch64__)
#error This check must be compiled for AArch64
#endif

static_assert (sizeof (void *) == sizeof (uint64_t));
static_assert (((0x10000U + 0x10000U - 16U) & 15U) == 0);

extern "C" __attribute__ ((noinline)) void
check_dcrt0_stack_switch (void *stackaddr)
{
  __asm__ ("\n\
	   mov sp, %[ADDR] \n\
	   mov fp, xzr     \n"
	   : : [ADDR] "r" (stackaddr)
	   : "memory");
}
