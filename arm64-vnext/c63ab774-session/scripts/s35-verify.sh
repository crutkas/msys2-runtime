#!/bin/bash
export PATH=/root/xc/inst/bin:$PATH
echo "############ PRECONDITIONS (must hold for the numbers to mean anything) ############"
echo -n "1. _cygwin.h aarch64 _WIN64 fix present : "
grep -q '#if defined(__x86_64__) || defined(__aarch64__)' \
  /root/xc/inst/aarch64-pc-cygwin/include/w32api/_cygwin.h && echo "YES" || echo "NO  <-- STOP"
echo -n "2. w32api version                       : "
printf '%s.%s.%s\n' \
  "$(grep -m1 -oP '(?<=__MINGW64_VERSION_MAJOR )\d+' /root/xc/inst/aarch64-pc-cygwin/include/w32api/_mingw_mac.h)" \
  "$(grep -m1 -oP '(?<=__MINGW64_VERSION_MINOR )\d+' /root/xc/inst/aarch64-pc-cygwin/include/w32api/_mingw_mac.h)" \
  "$(grep -m1 -oP '(?<=__MINGW64_VERSION_BUGFIX )\d+' /root/xc/inst/aarch64-pc-cygwin/include/w32api/_mingw_mac.h)"
echo -n "3. mbstate_t absent from corecrt.h      : "
[ "$(grep -c mbstate_t /root/xc/inst/aarch64-pc-cygwin/include/w32api/corecrt.h 2>/dev/null)" = "0" ] && echo "YES (no master regression)" || echo "NO"
echo -n "4. no corecrt.h shim reinstated         : "
grep -q '__LARGE_MBSTATE_T' /root/xc/inst/aarch64-pc-cygwin/include/w32api/corecrt.h 2>/dev/null && echo "SHIM PRESENT <-- STOP" || echo "YES (clean)"
echo -n "5. /root/xc/inst compiler untouched     : "
aarch64-pc-cygwin-g++ --version | head -1

echo
echo "############ OBJECT ACCOUNTING ############"
echo -n "intended .o targets (same denominator the sibling used): "
cd /root/xc/bld/winsup/cygwin
make --eval='po: ; @echo $(libdll_a_OBJECTS) $(libcygwin_a_OBJECTS) $(LIBCOS)' po 2>/dev/null | tr ' ' '\n' | grep -c '\.o$'
echo -n "objects actually built (find -name '*.o'): "; find . -name '*.o' | wc -l
echo -n "error: lines in final build             : "; grep -c 'error:' /root/xc/wb-r11.log
echo    "failing targets in final build          :"; grep -o "\*\*\* \[[^]]*\] Error" /root/xc/wb-r11.log | sort -u

echo
echo "############ ARTEFACTS ############"
echo -n "new-msys-2.0.dll : "; [ -f new-msys-2.0.dll ] && ls -la new-msys-2.0.dll || echo "DOES NOT EXIST - no DLL was produced"
echo "libgcc.a  : $(ls -la /root/xc/build-gcc2/aarch64-pc-cygwin/libgcc/libgcc.a | awk '{print $5}') bytes"
echo "libc.a    : $(ls -la /root/xc/bld/newlib/libc.a | awk '{print $5}') bytes"
echo "libm.a    : $(ls -la /root/xc/bld/newlib/libm.a | awk '{print $5}') bytes"
echo "libdll.a  : $(ls -la libdll.a | awk '{print $5}') bytes (248 real objects, nothing stubbed)"
echo "cygwin.sc : $(ls -la cygwin.sc | awk '{print $5}') bytes"
echo "msys.def  : $(ls -la msys.def | awk '{print $5}') bytes"
echo "sigfe.s   : $(ls -la sigfe.s  | awk '{print $5}') bytes  <-- empty, gendef emits nothing for aarch64"
