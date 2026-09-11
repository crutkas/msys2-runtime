/* The legacy table is an array alias, not the locale's mutable table pointer. */
#include <ctype.h>
#include <dlfcn.h>
#include <locale.h>
#include <stdio.h>
#include <string.h>

static unsigned char
ascii_mask (unsigned c)
{
  unsigned mask = 0;
  if (c < 32 || c == 127)
    mask |= _C;
  if (c == ' ' || (c >= '\t' && c <= '\r'))
    mask |= _S;
  if (c == ' ')
    mask |= _B;
  if (c >= '0' && c <= '9')
    mask |= _N;
  if (c >= 'A' && c <= 'Z')
    mask |= _U;
  if (c >= 'a' && c <= 'z')
    mask |= _L;
  if ((c >= 'A' && c <= 'F') || (c >= 'a' && c <= 'f'))
    mask |= _X;
  if (c >= '!' && c <= '~' && !(mask & (_U | _L | _N)))
    mask |= _P;
  return mask;
}

int
main (void)
{
  unsigned char classic[257];
  if (!setlocale (LC_ALL, "C"))
    {
      perror ("setlocale C");
      return 1;
    }
  if (dlsym (RTLD_DEFAULT, "_ctype_") != (const void *) _ctype_
      || __locale_ctype_ptr () != _ctype_ || _ctype_[0] != 0)
    {
      fprintf (stderr, "ctype export is not the original C table array\n");
      return 1;
    }
  for (unsigned c = 0; c < 256; ++c)
    {
      unsigned char mask = (unsigned char) _ctype_[c + 1];
      if (mask != ascii_mask (c) || !!isalpha (c) != !!(mask & (_U | _L))
	  || !!isdigit (c) != !!(mask & _N) || !!isspace (c) != !!(mask & _S))
	{
	  fprintf (stderr, "ctype table mismatch at %u: %#x\n", c, mask);
	  return 1;
	}
    }
  memcpy (classic, _ctype_, sizeof classic);
  if (!setlocale (LC_CTYPE, "C.UTF-8"))
    {
      fprintf (stderr, "C.UTF-8 locale is unavailable\n");
      return 1;
    }
  if (memcmp (classic, _ctype_, sizeof classic) != 0
      || dlsym (RTLD_DEFAULT, "_ctype_") != (const void *) _ctype_)
    {
      fprintf (stderr, "legacy ctype table identity changed with locale\n");
      return 1;
    }
  if (!setlocale (LC_CTYPE, "en_US.ISO-8859-1"))
    {
      fprintf (stderr, "ISO-8859-1 locale is unavailable\n");
      return 1;
    }
  if (__locale_ctype_ptr () == _ctype_ || !isalpha (0xc4)
      || (unsigned char) _ctype_[0xc4 + 1] != 0
      || memcmp (classic, _ctype_, sizeof classic) != 0)
    {
      fprintf (stderr, "classic ctype array was confused with the locale table\n");
      return 1;
    }
  return 0;
}
