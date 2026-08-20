/* aarch64-wsock-autoload-smoke.c

   Regression probe for the AArch64 dll_chain -> _wsock_init autoload path
   in winsup/cygwin/autoload.cc.

   ws2_32's dll_info->init slot is permanently set to _wsock_init (see
   LoadDLLprime (ws2_32, _wsock_init, 0)), so *every* not-yet-resolved
   ws2_32 function -- not just WSAStartup -- is first reached via
   dll_chain's tail branch into _wsock_init.  On AArch64, that entry
   happens through a plain "br", not a "bl"/"blr" call, so x30 does not
   hold a usable return address the way it does for the analogous
   std_dll_init hop.  Before the fix, _wsock_init reused
   INIT_WRAPPER's "mov x0, x30" and handed wsock_init() a stale x30
   (pointing into dll_chain's own code) as its func_info* argument,
   corrupting the resolver and adding a stack frame that was never
   popped; the process reliably crashed with an access violation the
   first time any ws2_32 function was autoloaded.

   This program must run as the very first thing in a fresh process so
   the plain LoadDLLfunc trampolines for `socket` (called directly from
   fhandler_socket_inet::socket) and `WSAEventSelect` (called from
   fhandler_socket_wsock::init_events, invoked from the same socket()
   call) are each still unresolved and must go through _wsock_init.  A
   clean, non-crashing exit proves the AArch64 fix in autoload.cc. */

#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>

int
main (void)
{
  int fd = socket (AF_INET, SOCK_STREAM, 0);

  if (fd < 0)
    return 1;
  if (close (fd) != 0)
    return 2;
  return 0;
}
