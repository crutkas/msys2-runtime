#!/bin/bash
# TEST: link with ASLR DISABLED.
#
# Cygwin/MSYS2 require msys-2.0.dll at a FIXED base: fork() copies the address
# space and the runtime must sit at the same address in parent and child. That
# is also why the identical absolute `.quad 1b` autoload construct is safe on
# x86_64 -- the image is never relocated, so the slots never need fixing up.
#
# Our link produced DllCharacteristics 0x0160 (DYNAMIC_BASE | HIGH_ENTROPY_VA |
# NX_COMPAT), so the loader relocated the image to 0x00007FFDAD3D0000 and every
# unrelocated absolute quad became a stale pointer.
set -u
export PATH=/root/xc/inst/bin:$PATH
export CPLUS_INCLUDE_PATH=/root/xc/sysroot-cxx/include/c++/15.0.1
L=/root/xc/w-link
cd $L/bld/winsup/cygwin || exit 1

echo "=== does this ld support the flags? ==="
aarch64-pc-cygwin-ld --help 2>&1 | grep -iE 'disable-dynamicbase|disable-high-entropy|dynamicbase' | head -4

rm -f new-msys-2.0-fixedbase.dll
aarch64-pc-cygwin-g++ -g -O2 -mno-use-libstdc-wrappers \
  -Wl,--gc-sections -nostdlib -Wl,-Tcygwin.sc -static \
  -Wl,--disable-dynamicbase -Wl,--disable-high-entropy-va \
  -Wl,--image-base,0x180000000 \
  -Wl,--heap=0 -Wl,--out-implib,msysdll-fb.a -shared -o new-msys-2.0-fixedbase.dll \
  -e dll_entry msys.def \
  -Wl,-whole-archive libdll.a -Wl,-no-whole-archive \
  version.o /root/xc/bld/winsup/cygserver/libcygserver.a \
  $L/bld/newlib/libm.a $L/bld/newlib/libc.a \
  -L/root/xc/build-gcc2/aarch64-pc-cygwin/libgcc -L/root/xc/implibs/lib \
  -lgcc -lkernel32 -lntdll -Wl,-Map,msys-fb.map > /root/xc/link-fixedbase.log 2>&1
echo "LINK EXIT $?   diagnostics bytes: $(wc -c < /root/xc/link-fixedbase.log)"
head -5 /root/xc/link-fixedbase.log

if [ -f new-msys-2.0-fixedbase.dll ]; then
  ls -la new-msys-2.0-fixedbase.dll
  python3 -B /root/xc/t/sA8.py new-msys-2.0-fixedbase.dll
  printf 'sha256 %s\n' "$(sha256sum new-msys-2.0-fixedbase.dll | cut -c1-64)"
  printf 'tpidr_el0 in image: %s\n' "$(aarch64-pc-cygwin-objdump -d new-msys-2.0-fixedbase.dll 2>/dev/null | grep -c tpidr_el0)"
  cp new-msys-2.0-fixedbase.dll \
     /mnt/c/Users/crutkasLocal/.copilot/session-state/c63ab774-a023-4e57-9bc4-53f727507ada/files/runtest/msys-2.0-fixedbase.dll
  echo "copied to Windows."
fi
