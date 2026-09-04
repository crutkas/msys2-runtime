#!/bin/bash
# Rebuild pseudo-reloc.o, regenerate cygwin.sc, relink, and stage.
set -u
export PATH=/root/xc/inst/bin:$PATH
L=/root/xc/w-link
B=$L/bld/winsup/cygwin
D=/mnt/c/Users/crutkasLocal/.copilot/session-state/c63ab774-a023-4e57-9bc4-53f727507ada/files/runtest
cd $B || exit 1

echo "=== regenerate cygwin.sc ==="
cp cygwin.sc /tmp/cygwin.sc.prev
make cygwin.sc 2>&1 | tail -3
echo "--- diff of generated linker script ---"
diff /tmp/cygwin.sc.prev cygwin.sc
echo "(diff exit $?)"

echo
echo "=== rebuild pseudo-reloc.o ==="
INCLUDES="$(sed -n 's/^AM_CPPFLAGS = //p' Makefile | head -1)"
make pseudo-reloc.o INCLUDES="$INCLUDES" 2>&1 | tail -3

echo
echo "=== relink ==="
make msys-2.0.dll INCLUDES="$INCLUDES" > /tmp/link-harden.log 2>&1
echo "LINK EXIT $?  diagnostics bytes: $(stat -c%s /tmp/link-harden.log)"

if [ -f msys-2.0.dll ]; then
  echo
  echo "=== .xdata / .pdata section layout ==="
  aarch64-pc-cygwin-objdump -h msys-2.0.dll | grep -E 'Idx|xdata|pdata'
  printf 'DLL sha256 %s\n' "$(sha256sum msys-2.0.dll | cut -c1-64)"
  cp msys-2.0.dll $D/msys-2.0.dll
  cp msys-2.0.dll $D/msys-2.0-hardened.dll
  echo staged.
fi
