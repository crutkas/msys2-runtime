#include <pthread.h>
#include <windows.h>

#include <cstdint>
#include <iostream>
#include <mutex>
#include <thread>

#if !defined(__aarch64__)
#error This check must be compiled for AArch64
#endif

namespace {
constinit std::mutex gate;
int startup_state;
int total;

struct Startup
{
  Startup () { startup_state = 41; }
};

Startup startup;

void
add (int value)
{
  std::lock_guard<std::mutex> lock (gate);
  total += value;
}

void *
pthread_entry (void *context)
{
  add (*static_cast<int *> (context));
  return nullptr;
}
}

int
main ()
{
  if (startup_state != 41)
    return 1;

  pthread_t pthread;
  int pthread_value = 17;
  if (pthread_create (&pthread, nullptr, pthread_entry, &pthread_value) != 0)
    return 2;

  std::thread cpp_thread (add, 25);
  cpp_thread.join ();
  if (pthread_join (pthread, nullptr) != 0)
    return 3;
  if (total != 42)
    return 4;

  HMODULE image = GetModuleHandleW (NULL);
  HMODULE libstdcxx = GetModuleHandleA ("msys-stdc++-6.dll");
  if (!image || !libstdcxx)
    return 5;

  uintptr_t image_address = reinterpret_cast<uintptr_t> (image);
  uintptr_t libstdcxx_address = reinterpret_cast<uintptr_t> (libstdcxx);
  uintptr_t distance = image_address >= libstdcxx_address
		       ? image_address - libstdcxx_address
		       : libstdcxx_address - image_address;

  std::cout << "dynamic-cxx-ok total=" << total
	    << " module-distance=0x" << std::hex << distance << std::endl;
  return 0;
}
