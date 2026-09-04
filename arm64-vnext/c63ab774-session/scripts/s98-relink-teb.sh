#!/bin/bash
# Relink using the TEB-fixed newlib in w-link (not the preserved one).
set -u
export PATH=/root/xc/inst/bin:$PATH
export CPLUS_INCLUDE_PATH=/root/xc/sysroot-cxx/include/c++/15.0.1
L=/root/xc/w-link
R=$L/runtime/winsup/cygwin
cd $L/bld/winsup/cygwin || exit 1

rm -f libdll.a new-msys-2.0.dll
make --eval='po: ; @echo $(libdll_a_OBJECTS)' po 2>/dev/null | tr ' ' '\n' | grep -v '^$' | sort -u > /tmp/z_all.txt
: > /tmp/z_have.txt
while read -r o; do [ -f "$o" ] && echo "$o" >> /tmp/z_have.txt; done < /tmp/z_all.txt
echo "fenv_aarch64.o" >> /tmp/z_have.txt
xargs -a /tmp/z_have.txt aarch64-pc-cygwin-ar cr libdll.a
aarch64-pc-cygwin-ranlib libdll.a
printf 'libdll.a objects: %s\n' "$(wc -l < /tmp/z_have.txt)"

aarch64-pc-cygwin-g++ -g -O2 -mno-use-libstdc-wrappers \
  -Wl,--gc-sections -nostdlib -Wl,-Tcygwin.sc -static \
  -Wl,--heap=0 -Wl,--out-implib,msysdll.a -shared -o new-msys-2.0.dll \
  -e dll_entry msys.def \
  -Wl,-whole-archive libdll.a -Wl,-no-whole-archive \
  version.o /root/xc/bld/winsup/cygserver/libcygserver.a \
  $L/bld/newlib/libm.a $L/bld/newlib/libc.a \
  -L/root/xc/build-gcc2/aarch64-pc-cygwin/libgcc -L/root/xc/implibs/lib \
  -lgcc -lkernel32 -lntdll -Wl,-Map,msys.map > /root/xc/link-teb2.log 2>&1
echo "LINK EXIT $?   diagnostics bytes: $(wc -c < /root/xc/link-teb2.log)"
cat /root/xc/link-teb2.log | head -10

echo
echo "=== TEB idiom audit in the final image ==="
printf 'mrs tpidr_el0 : %s  (want 0)\n' "$(aarch64-pc-cygwin-objdump -d new-msys-2.0.dll 2>/dev/null | grep -c tpidr_el0)"
printf 'mov xN, x18   : %s\n' "$(aarch64-pc-cygwin-objdump -d new-msys-2.0.dll 2>/dev/null | grep -cE 'mov[[:space:]]+x[0-9]+, x18')"
ls -la new-msys-2.0.dll
printf 'sha256 %s\n' "$(sha256sum new-msys-2.0.dll | cut -c1-64)"

# name it findable, per the coordinator's note about globbing
DEST=/mnt/c/Users/crutkasLocal/.copilot/session-state/c63ab774-a023-4e57-9bc4-53f727507ada/files/runtest
cp new-msys-2.0.dll $DEST/msys-2.0-teb.dll
echo "copied to $DEST/msys-2.0-teb.dll"
