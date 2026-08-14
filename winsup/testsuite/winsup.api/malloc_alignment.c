#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#define CYGWIN_MALLOC_ALIGNMENT 16

typedef unsigned char vector128
  __attribute__ ((__vector_size__ (16)));

_Static_assert (_Alignof (max_align_t) <= CYGWIN_MALLOC_ALIGNMENT,
		"malloc must satisfy max_align_t");
_Static_assert (_Alignof (long double) <= CYGWIN_MALLOC_ALIGNMENT,
		"malloc must satisfy long double alignment");
_Static_assert (_Alignof (vector128) <= CYGWIN_MALLOC_ALIGNMENT,
		"malloc must satisfy 128-bit SIMD alignment");

static int
check_alignment (const char *operation, size_t size, void *ptr)
{
  if (!ptr)
    {
      fprintf (stderr, "%s (%zu) returned NULL\n", operation, size);
      return 1;
    }

  if ((uintptr_t) ptr % CYGWIN_MALLOC_ALIGNMENT != 0)
    {
      fprintf (stderr, "%s (%zu) returned unaligned pointer %p\n",
	       operation, size, ptr);
      return 1;
    }

  return 0;
}

int
main ()
{
  static const size_t sizes[] =
    {
      1, 2, 7, 8, 15, 16, 17, 31, 32, 33,
      63, 64, 65, 127, 128, 129, 255, 256, 257,
      1023, 1024, 1025, 4095, 4096, 4097
    };
  void *ptr = NULL;

  for (size_t i = 0; i < sizeof (sizes) / sizeof (sizes[0]); ++i)
    {
      ptr = malloc (sizes[i]);
      if (check_alignment ("malloc", sizes[i], ptr))
	return 1;
      free (ptr);

      ptr = calloc (1, sizes[i]);
      if (check_alignment ("calloc", sizes[i], ptr))
	return 1;
      free (ptr);
    }

  ptr = malloc (1);
  if (check_alignment ("malloc", 1, ptr))
    return 1;

  for (size_t i = 0; i < sizeof (sizes) / sizeof (sizes[0]); ++i)
    {
      void *resized = realloc (ptr, sizes[i]);
      if (check_alignment ("realloc", sizes[i], resized))
	return 1;
      ptr = resized;
    }

  free (ptr);
  return 0;
}
