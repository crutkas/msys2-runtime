#include "winsup.h"
#include "cygtls.h"

extern "C" __attribute__ ((noinline, used)) void
check_cygtls_lock (_cygtls *tls)
{
  tls->lock ();
}
