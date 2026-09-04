#!/bin/bash
cd /root/xc || exit 1
hashone() {
  printf '%-56s %10s  %s\n' "$1" "$(stat -c%s "$1" 2>/dev/null)" "$(sha256sum "$1" 2>/dev/null | cut -c1-64)"
}
echo "=== PRESERVED PROGRAMME ASSETS (WSL, /root/xc) ==="
for f in \
  bld/newlib/libc.a \
  bld/newlib/libm.a \
  build-gcc2/aarch64-pc-cygwin/libgcc/libgcc.a \
  implibs/lib/libkernel32.a \
  implibs/lib/libntdll.a \
  implibs/lib/libadvapi32.a \
  implibs/lib/libuser32.a \
  bld/winsup/cygwin/cygwin.sc \
  bld/winsup/cygwin/msys.def \
  bld/winsup/cygwin/sigfe.s \
  bld/winsup/cygwin/libdll.a \
  bld/winsup/cygwin/msysdll.a ; do
  hashone "$f"
done

echo
echo "=== FREESTANDING C++ HEADERS (/root/xc/sysroot-cxx) ==="
find sysroot-cxx -type f | sort | while read -r h; do hashone "$h"; done

echo
echo "=== CONFIRM: no DLL anywhere in the build tree ==="
find /root/xc -name '*msys-2.0.dll' 2>/dev/null | head
echo "(no line above == no DLL exists)"

echo
echo "=== CONFIRM: /root/xc/inst compiler unchanged ==="
export PATH=/root/xc/inst/bin:$PATH
aarch64-pc-cygwin-g++ --version | head -1
aarch64-pc-cygwin-ld --version | head -1
