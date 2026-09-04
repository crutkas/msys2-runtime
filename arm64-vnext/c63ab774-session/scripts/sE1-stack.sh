#!/bin/bash
# STATUS_STACK_OVERFLOW (0xC00000FD). Distinguish INFINITE RECURSION from a
# merely deep-but-finite stack by relinking with a much larger reserve.
set -u
export PATH=/root/xc/inst/bin:$PATH
L=/root/xc/w-link
R=$L/runtime/winsup/cygwin
B=$L/bld/winsup/cygwin
D=/mnt/c/Users/crutkasLocal/.copilot/session-state/c63ab774-a023-4e57-9bc4-53f727507ada/files/runtest
cd $B || exit 1

echo "=== identity check: is the staged DLL the ctor-fix build? ==="
printf 'staged  : %s\n' "$(sha256sum $D/msys-2.0.dll | cut -c1-64)"
printf 'ctorfix : %s\n' "$(sha256sum $D/msys-2.0-ctorfix.dll | cut -c1-64)"
[ "$(sha256sum $D/msys-2.0.dll | cut -c1-64)" = "$(sha256sum $D/msys-2.0-ctorfix.dll | cut -c1-64)" ] \
  && echo "MATCH - the ctor-fixed runtime is what ran" || echo "MISMATCH <<<"

echo
echo "=== relink rung3 with a 64 MB stack reserve ==="
cat > /tmp/rung3.c <<'EOF'
int main (void)
{
  return 77;
}
EOF
aarch64-pc-cygwin-gcc -g -O0 -nostdlib -nostartfiles \
  -isystem $R/include -isystem /root/xc/bld/newlib/targ-include \
  -isystem $L/runtime/newlib/libc/include \
  -isystem /root/xc/inst/aarch64-pc-cygwin/include/w32api \
  -Wl,--stack,0x4000000 \
  -o rung3-bigstack.exe \
  $B/crt0.o /tmp/rung3.c $B/libmsys-2.0.a \
  -L/root/xc/build-gcc2/aarch64-pc-cygwin/libgcc -lgcc \
  -L/root/xc/implibs/lib -lkernel32 2>&1 | head -5
echo "LINK EXIT ${PIPESTATUS[0]}"
ls -la rung3-bigstack.exe 2>&1
cp rung3-bigstack.exe $D/ 2>/dev/null

echo
echo "=== stack reserve actually recorded in each image ==="
python3 -B - <<'PY'
import struct
for f in ("/root/xc/w-link/bld/winsup/cygwin/rung3.exe",
          "/root/xc/w-link/bld/winsup/cygwin/rung3-bigstack.exe"):
    try:
        d=open(f,"rb").read()
        pe=struct.unpack_from("<I",d,0x3C)[0]
        opt=pe+24
        res=struct.unpack_from("<Q",d,opt+72)[0]
        com=struct.unpack_from("<Q",d,opt+80)[0]
        print("%-40s reserve=0x%X commit=0x%X" % (f.split('/')[-1],res,com))
    except Exception as e:
        print(f,"->",e)
PY
