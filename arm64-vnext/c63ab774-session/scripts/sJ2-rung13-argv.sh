#!/bin/bash
set -u
export PATH=/root/xc/inst/bin:$PATH
L=/root/xc/w-link; R=$L/runtime/winsup/cygwin; B=$L/bld/winsup/cygwin
D=/mnt/c/Users/crutkasLocal/.copilot/session-state/c63ab774-a023-4e57-9bc4-53f727507ada/files/runtest
cd $B || exit 1
cat > /tmp/rung13.c <<'EOF'
#include <stdio.h>
#include <string.h>
int main (int argc, char **argv)
{
  int bad = 0;
  printf ("argc=%d\n", argc);
  for (int i = 1; i < argc; i++)
    printf ("  argv[%d] = [%s]  len=%d\n", i, argv[i], (int) strlen (argv[i]));
  if (argc > 1 && strcmp (argv[1], "abcdefg") != 0) bad = 1;
  if (argc > 2 && strcmp (argv[2], "abcdefghijklmnop") != 0) bad = 1;
  if (argc > 3 && strcmp (argv[3], "abcdefghijklmnopqrstuvwx") != 0) bad = 1;
  printf ("VERDICT: %s\n", bad ? "CORRUPT" : "ALL ARGS INTACT");
  return bad ? 1 : 55;
}
EOF
aarch64-pc-cygwin-gcc -g -O0 -nostdlib -nostartfiles \
  -isystem $R/include -isystem /root/xc/bld/newlib/targ-include \
  -isystem $L/runtime/newlib/libc/include \
  -o rung13.exe $B/crt0.o /tmp/rung13.c $B/libmsys-2.0.a \
  -L/root/xc/build-gcc2/aarch64-pc-cygwin/libgcc -lgcc \
  -L/root/xc/implibs/lib -lkernel32 2>&1 | head -5
echo "LINK EXIT ${PIPESTATUS[0]}"
[ -f rung13.exe ] && cp rung13.exe $D/ && echo "staged rung13.exe"