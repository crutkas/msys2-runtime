#include <ctype.h>

#if !defined(__aarch64__)
#error This check must be compiled for AArch64
#endif

#define EXPORT __attribute__ ((dllexport))

EXPORT const char *
direct_ctype_table (void)
{
  return _ctype_ + 1;
}

EXPORT const char *
locale_ctype_table (void)
{
  return __locale_ctype_ptr () + 1;
}

#ifdef ABI_RUNTIME_TEST

static int
has_class (const unsigned char *table, unsigned char c, unsigned char mask)
{
  return (table[c] & mask) == mask;
}

int
main (void)
{
  const unsigned char *direct =
    (const unsigned char *) direct_ctype_table ();
  const unsigned char *locale =
    (const unsigned char *) locale_ctype_table ();

  if (direct != locale)
    return 1;
  if (!has_class (direct, 'A', _U | _X)
      || !has_class (direct, 'a', _L | _X)
      || !has_class (direct, '0', _N)
      || !has_class (direct, ' ', _S | _B)
      || !has_class (direct, '\n', _C | _S)
      || !has_class (direct, '!', _P))
    return 2;
  if (!isalpha ('A') || !islower ('a') || !isdigit ('0') || !isxdigit ('F')
      || !isspace (' ') || !iscntrl ('\n') || !ispunct ('!'))
    return 3;

  return 0;
}

#endif
