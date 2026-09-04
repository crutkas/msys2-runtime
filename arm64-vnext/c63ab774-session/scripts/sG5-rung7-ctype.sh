#!/bin/bash
# Rung 7: ctype. Verify the coordinator's finding ON MY OWN BUILD, empirically,
# rather than trusting a symbol table reading or a report.
set -u
export PATH=/root/xc/inst/bin:$PATH
L=/root/xc/w-link
R=$L/runtime/winsup/cygwin
B=$L/bld/winsup/cygwin
D=/mnt/c/Users/crutkasLocal/.copilot/session-state/c63ab774-a023-4e57-9bc4-53f727507ada/files/runtest
cd $B || exit 1

cat > /tmp/rung7.c <<'EOF'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

/* One function per run, selected by exit code, so a crash in one does not
   mask the others. Run with no args -> run them all in sequence, printing
   before each so the last line printed names the one that died. */
int
main (void)
{
  printf ("A strlen  -> %d\n", (int) strlen ("hello arm64 world")); fflush (stdout);
  printf ("B abs     -> %d\n", abs (-42)); fflush (stdout);
  printf ("C toupper -> %d\n", toupper (97)); fflush (stdout);
  printf ("D tolower -> %d\n", tolower (65)); fflush (stdout);
  printf ("E isalpha -> %d\n", isalpha (97) ? 1 : 0); fflush (stdout);
  printf ("F isdigit -> %d\n", isdigit ('7') ? 1 : 0); fflush (stdout);
  printf ("G isspace -> %d\n", isspace (' ') ? 1 : 0); fflush (stdout);
  printf ("H atoi    -> %d\n", atoi ("12345")); fflush (stdout);
  printf ("I strtol  -> %ld\n", strtol ("6789", NULL, 10)); fflush (stdout);
  printf ("ALL CTYPE OK\n"); fflush (stdout);
  return 44;
}
EOF

aarch64-pc-cygwin-gcc -g -O0 -nostdlib -nostartfiles \
  -isystem $R/include -isystem /root/xc/bld/newlib/targ-include \
  -isystem $L/runtime/newlib/libc/include \
  -o rung7.exe $B/crt0.o /tmp/rung7.c $B/libmsys-2.0.a \
  -L/root/xc/build-gcc2/aarch64-pc-cygwin/libgcc -lgcc \
  -L/root/xc/implibs/lib -lkernel32 2>&1 | head -10
echo "LINK EXIT ${PIPESTATUS[0]}"
[ -f rung7.exe ] && cp rung7.exe $D/ && echo "staged rung7.exe"

echo
echo "=== who references __ctype_b (two underscores)? ==="
for o in $(find . -name '*.o' | head -400); do
  if aarch64-pc-cygwin-nm "$o" 2>/dev/null | grep -q "U __ctype_b"; then echo "  $o"; fi
done | head -20
echo
echo "=== source references ==="
grep -rn "__ctype_b\b" $L/runtime/winsup/cygwin $L/runtime/newlib/libc/include 2>/dev/null | head -10
echo
echo "=== who DEFINES _ctype_b ==="
grep -rn "_ctype_b\b" $L/runtime/newlib/libc/ctype/*.c $L/runtime/newlib/libc/include/*.h 2>/dev/null | head -10
