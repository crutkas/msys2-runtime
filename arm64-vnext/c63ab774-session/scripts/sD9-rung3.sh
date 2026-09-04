#!/bin/bash
# RUNG 3: build a trivial MSYS2/Cygwin executable against the ARM64 runtime.
# Distinctive exit code 77 so success cannot be confused with an accidental 0.
set -u
export PATH=/root/xc/inst/bin:$PATH
L=/root/xc/w-link
R=$L/runtime/winsup/cygwin
B=$L/bld/winsup/cygwin
D=/mnt/c/Users/crutkasLocal/.copilot/session-state/c63ab774-a023-4e57-9bc4-53f727507ada/files/runtest
cd $B || exit 1

cat > /tmp/rung3.c <<'EOF'
/* Rung 3: the smallest possible real process. Returns a distinctive value so a
   pass cannot be confused with an accidental 0. */
int main (void)
{
  return 77;
}
EOF

echo "=== compile + link against the ARM64 msys runtime ==="
aarch64-pc-cygwin-gcc -g -O0 \
  -nostdlib -nostartfiles \
  -isystem $R/include \
  -isystem /root/xc/bld/newlib/targ-include \
  -isystem $L/runtime/newlib/libc/include \
  -isystem /root/xc/inst/aarch64-pc-cygwin/include/w32api \
  -o rung3.exe \
  $B/crt0.o /tmp/rung3.c \
  $B/libmsys-2.0.a \
  -L/root/xc/build-gcc2/aarch64-pc-cygwin/libgcc -lgcc \
  -L/root/xc/implibs/lib -lkernel32 \
  2>&1 | head -20
echo "LINK EXIT ${PIPESTATUS[0]}"
ls -la rung3.exe 2>&1

if [ -f rung3.exe ]; then
  echo
  echo "=== verify it is an ARM64 PE ==="
  aarch64-pc-cygwin-objdump -f rung3.exe | head -4
  echo "=== what does it import? ==="
  aarch64-pc-cygwin-objdump -p rung3.exe 2>/dev/null | grep -i 'DLL Name' | sort -u
  cp rung3.exe $D/rung3.exe
  # the import library references msys-2.0.dll by name
  cp new-msys-2.0.dll $D/msys-2.0.dll
  printf 'exe sha256 %s\n' "$(sha256sum rung3.exe | cut -c1-64)"
  echo "staged in $D alongside msys-2.0.dll"
fi
