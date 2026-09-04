#!/bin/bash
# Rung 4: printf -- pulls in stdio, locale, and much more of libc.
set -u
export PATH=/root/xc/inst/bin:$PATH
L=/root/xc/w-link
R=$L/runtime/winsup/cygwin
B=$L/bld/winsup/cygwin
D=/mnt/c/Users/crutkasLocal/.copilot/session-state/c63ab774-a023-4e57-9bc4-53f727507ada/files/runtest
cd $B || exit 1

cat > /tmp/rung4.c <<'EOF'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main (void)
{
  char *p = (char *) malloc (64);
  if (!p)
    return 91;
  strcpy (p, "hello from ARM64 msys2-runtime");
  printf ("%s\n", p);
  printf ("sizeof(void*)=%d\n", (int) sizeof (void *));
  free (p);
  fflush (stdout);
  return 42;
}
EOF

aarch64-pc-cygwin-gcc -g -O0 -nostdlib -nostartfiles \
  -isystem $R/include -isystem /root/xc/bld/newlib/targ-include \
  -isystem $L/runtime/newlib/libc/include \
  -o rung4.exe $B/crt0.o /tmp/rung4.c $B/libmsys-2.0.a \
  -L/root/xc/build-gcc2/aarch64-pc-cygwin/libgcc -lgcc \
  -L/root/xc/implibs/lib -lkernel32 2>&1 | head -10
echo "LINK EXIT ${PIPESTATUS[0]}"
ls -la rung4.exe 2>&1
[ -f rung4.exe ] && cp rung4.exe $D/ && printf 'rung4 sha256 %s\n' "$(sha256sum rung4.exe | cut -c1-64)"
