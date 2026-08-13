#define _LIBC 1
#include <cygwin/config.h>

struct _reent *
check_getreent (void)
{
  return __getreent ();
}
