#include <stdlib.h>
#include <string.h>

static char *
reference_strchr (const char *s, int c)
{
  unsigned char needle = (unsigned char) c;

  do
    {
      if ((unsigned char) *s == needle)
	return (char *) s;
    }
  while (*s++);
  return NULL;
}

int
main (void)
{
  static char storage[256 + 64];
  char *(*volatile tested_strchr) (const char *, int) = strchr;

  for (unsigned int offset = 0; offset < 64; ++offset)
    {
      char *text = storage + offset;

      for (unsigned int length = 0; length < 128; ++length)
	{
	  for (unsigned int i = 0; i < length; ++i)
	    text[i] = (char) (1 + ((i * 37 + offset * 11) % 255));
	  text[length] = '\0';

	  for (unsigned int needle = 0; needle < 256; ++needle)
	    if (tested_strchr (text, needle)
		!= reference_strchr (text, needle))
	      abort ();
	}
    }
  return 0;
}
