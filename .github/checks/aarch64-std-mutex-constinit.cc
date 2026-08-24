#include <mutex>

#if !defined(__aarch64__)
#error This check must be compiled for AArch64
#endif

constinit std::mutex abi_std_mutex;

extern "C" __attribute__ ((dllexport)) std::mutex *
abi_std_mutex_address ()
{
  return &abi_std_mutex;
}
