#include <stddef.h>
#include <stdint.h>
#include <sys/types.h>

#ifndef __aarch64__
#error "Expected an AArch64 compiler target"
#endif

#ifndef __CYGWIN__
#error "Expected a Cygwin compiler target"
#endif

#ifndef MALLOC_ALIGNMENT
#error "Expected newlib to define AArch64 malloc alignment"
#endif

#if MALLOC_ALIGNMENT != 16
#error "Expected 16-byte newlib AArch64 malloc alignment"
#endif

enum { newlib_malloc_alignment = MALLOC_ALIGNMENT };

#include "cygmalloc.h"

#if MALLOC_ALIGNMENT != 16
#error "Cygwin must preserve newlib's AArch64 malloc alignment"
#endif

typedef unsigned char vector128
  __attribute__ ((__vector_size__ (16)));

_Static_assert (MALLOC_ALIGNMENT == newlib_malloc_alignment,
		"Cygwin and newlib malloc alignment must match");
_Static_assert ((MALLOC_ALIGNMENT & (MALLOC_ALIGNMENT - 1)) == 0,
		"malloc alignment must be a power of two");
_Static_assert (sizeof (void *) == 8,
		"Windows AArch64 pointers must be 64-bit");
_Static_assert (_Alignof (max_align_t) == 8,
		"Windows AArch64 max_align_t must be 8-byte aligned");
_Static_assert (_Alignof (long double) == 8,
		"Windows AArch64 long double must be 8-byte aligned");
_Static_assert (_Alignof (vector128) == 16,
		"Windows AArch64 128-bit SIMD must be 16-byte aligned");
_Static_assert (_Alignof (max_align_t) <= MALLOC_ALIGNMENT
		&& _Alignof (long double) <= MALLOC_ALIGNMENT
		&& _Alignof (vector128) <= MALLOC_ALIGNMENT,
		"malloc must satisfy every target ABI alignment");

unsigned char checked_malloc_alignment[MALLOC_ALIGNMENT];
unsigned char checked_max_align_t_alignment[_Alignof (max_align_t)];
unsigned char checked_long_double_alignment[_Alignof (long double)];
unsigned char checked_vector_alignment[_Alignof (vector128)];
