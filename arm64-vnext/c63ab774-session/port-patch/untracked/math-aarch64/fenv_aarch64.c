/*
 * feenableexcept / fedisableexcept / fegetexcept for AArch64
 * Manipulate FPCR trap-enable bits (bits 8-12, 15).
 * Many ARM64 implementations treat these as RAZ/WI.
 */
#include <fenv.h>

#define FE_ALL_EXCEPT_VAL (FE_DIVBYZERO | FE_INEXACT | FE_INVALID | FE_OVERFLOW | FE_UNDERFLOW)
#define FPUSW_SHIFT 8
#define ENABLE_MASK (FE_ALL_EXCEPT_VAL << FPUSW_SHIFT)

int feenableexcept(int mask)
{
    unsigned long long old_r, new_r;
    __asm__ __volatile__("mrs %0, fpcr" : "=r" (old_r));
    new_r = old_r | ((mask & FE_ALL_EXCEPT_VAL) << FPUSW_SHIFT);
    __asm__ __volatile__("msr fpcr, %0" : : "r" (new_r));
    return ((old_r >> FPUSW_SHIFT) & FE_ALL_EXCEPT_VAL);
}

int fedisableexcept(int mask)
{
    unsigned long long old_r, new_r;
    __asm__ __volatile__("mrs %0, fpcr" : "=r" (old_r));
    new_r = old_r & ~((mask & FE_ALL_EXCEPT_VAL) << FPUSW_SHIFT);
    __asm__ __volatile__("msr fpcr, %0" : : "r" (new_r));
    return ((old_r >> FPUSW_SHIFT) & FE_ALL_EXCEPT_VAL);
}

int fegetexcept(void)
{
    unsigned long long r;
    __asm__ __volatile__("mrs %0, fpcr" : "=r" (r));
    return ((r & ENABLE_MASK) >> FPUSW_SHIFT);
}
