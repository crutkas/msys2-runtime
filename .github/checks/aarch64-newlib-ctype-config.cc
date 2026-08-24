#include <ctype.h>

#if !defined(__aarch64__)
#error This check must be compiled for AArch64
#endif

/* Mirrors libstdc++'s newlib ctype<char>::classic_table() dependency. */
extern "C" __attribute__ ((dllexport)) const char *
libstdcxx_newlib_classic_table (void)
{
  return _ctype_ + 1;
}
