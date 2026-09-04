#!/bin/bash
# THE DISCRIMINATOR: does the cygheap chain corruption require a user malloc?
#
# Sibling re-classified the wild values as ptmalloc SEGMENT BASES from
# win32mmap/win32direct_mmap (mm/malloc.cc:1670/1676), not mmap-arena
# addresses. If that is right, a program that NEVER calls user malloc should
# have a CLEAN, NULL-terminated chain, and one that calls malloc once should
# not. No debugger subtlety required -- just two programs and a chain walk.
set -u
export PATH=/root/xc/inst/bin:$PATH
L=/root/xc/w-link
R=$L/runtime/winsup/cygwin
B=$L/bld/winsup/cygwin
D=/mnt/c/Users/crutkasLocal/.copilot/session-state/c63ab774-a023-4e57-9bc4-53f727507ada/files/runtest
cd $B || exit 1

# rung9: NO user malloc, NO stdio (printf allocates stdio buffers). Just fault.
cat > /tmp/rung9.c <<'EOF'
int
main (void)
{
  /* No malloc, no stdio. The fault is only a capture mechanism. */
  * (volatile int *) 0 = 1;
  return 0;
}
EOF

# rung10: identical, except ONE user malloc before the fault.
cat > /tmp/rung10.c <<'EOF'
extern void *malloc (unsigned long);
extern void free (void *);
int
main (void)
{
  void *volatile p = malloc (64);
  free (p);
  * (volatile int *) 0 = 1;
  return 0;
}
EOF

for t in rung9 rung10; do
  aarch64-pc-cygwin-gcc -g -O0 -nostdlib -nostartfiles \
    -isystem $R/include -isystem /root/xc/bld/newlib/targ-include \
    -isystem $L/runtime/newlib/libc/include \
    -o $t.exe $B/crt0.o /tmp/$t.c $B/libmsys-2.0.a \
    -L/root/xc/build-gcc2/aarch64-pc-cygwin/libgcc -lgcc \
    -L/root/xc/implibs/lib -lkernel32 2>&1 | head -5
  echo "$t LINK EXIT ${PIPESTATUS[0]}"
  [ -f $t.exe ] && cp $t.exe $D/ && printf '  %s sha256 %s\n' "$t.exe" "$(sha256sum $t.exe | cut -c1-64)"
done
