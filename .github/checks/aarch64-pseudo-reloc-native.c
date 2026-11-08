#include <stdint.h>
#include <stdio.h>
#include <windows.h>

#if !defined(__aarch64__)
#error This check must be compiled for AArch64
#endif

extern volatile uint64_t aarch64_near_value;
extern unsigned char aarch64_far_object[];

static uintptr_t
distance_between (uintptr_t left, uintptr_t right)
{
  return left >= right ? left - right : right - left;
}

int
main ()
{
  HMODULE image = GetModuleHandleW (NULL);
  HMODULE near_module = GetModuleHandleA ("aarch64-near-import.dll");
  HMODULE far_module = GetModuleHandleA ("aarch64-far-import.dll");

  if (!image || !near_module || !far_module)
    return 1;
  if ((uintptr_t) image != UINT64_C (0x100400000)
      || (uintptr_t) near_module != UINT64_C (0x140040000)
      || (uintptr_t) far_module != UINT64_C (0x600040000))
    return 2;
  if (distance_between ((uintptr_t) image, (uintptr_t) far_module)
      <= UINT64_C (0x100000000))
    return 3;

  if (aarch64_near_value != UINT64_C (0x1122334455667788))
    return 4;
  aarch64_near_value = UINT64_C (0xa5a55a5adeadbeef);
  if (aarch64_near_value != UINT64_C (0xa5a55a5adeadbeef))
    return 5;

  uintptr_t far_address = (uintptr_t) &aarch64_far_object[0];
  if (far_address < (uintptr_t) far_module
      || far_address - (uintptr_t) far_module >= 0x10000)
    return 6;
  if (*((volatile uint64_t *) far_address)
      != UINT64_C (0x8877665544332211))
    return 7;

  printf ("pseudo-reloc-native-ok image=0x%llx near=0x%llx far=0x%llx "
	  "delta=0x%llx\n",
	  (unsigned long long) (uintptr_t) image,
	  (unsigned long long) (uintptr_t) near_module,
	  (unsigned long long) (uintptr_t) far_module,
	  (unsigned long long) distance_between (
	    (uintptr_t) image, (uintptr_t) far_module));
  return 0;
}
