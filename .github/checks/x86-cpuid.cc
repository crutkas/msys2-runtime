#include <stdint.h>

#include "cpuid.h"

extern "C" void
checked_cpuid (uint32_t *registers, uint32_t leaf, uint32_t subleaf)
{
  cpuid (registers, registers + 1, registers + 2, registers + 3, leaf,
	 subleaf);
}

extern "C" bool
checked_can_set_flag (uint32_t long flag)
{
  return can_set_flag (flag);
}
