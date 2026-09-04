#!/bin/bash
# Preconditions + confirm the remaining .align sites are x86-only.
L=/root/xc/w-link
W=/root/xc/inst/aarch64-pc-cygwin/include/w32api

echo "############ PRECONDITIONS ############"
echo -n "1. _cygwin.h aarch64 _WIN64 guard : "
grep -q '#if defined(__x86_64__) || defined(__aarch64__)' $W/_cygwin.h && echo "PRESENT" || echo "ABSENT <-- STOP"
echo -n "2. w32api version                 : "
printf '%s.%s.%s\n' \
  "$(grep -m1 -oP '(?<=__MINGW64_VERSION_MAJOR )\d+' $W/_mingw_mac.h)" \
  "$(grep -m1 -oP '(?<=__MINGW64_VERSION_MINOR )\d+' $W/_mingw_mac.h)" \
  "$(grep -m1 -oP '(?<=__MINGW64_VERSION_BUGFIX )\d+' $W/_mingw_mac.h)"
echo -n "3. mbstate_t in corecrt.h         : "
printf '%s (want 0)\n' "$(grep -c mbstate_t $W/corecrt.h 2>/dev/null)"
echo -n "4. corecrt shim reinstated        : "
grep -q '__LARGE_MBSTATE_T' $W/corecrt.h 2>/dev/null && echo "SHIM PRESENT <-- STOP" || echo "NO (clean)"
echo -n "5. mingw-w64 checkout commit      : "
git --no-optional-locks -C /root/xc/mingw-w64 rev-parse HEAD 2>/dev/null
echo -n "   expected v12.0.0               : 819a6ec2ea87c19814b287e21d65e0dc7f05abba"; echo
echo -n "   describe                       : "
git --no-optional-locks -C /root/xc/mingw-w64 describe --tags 2>/dev/null
echo -n "6. cross compiler                 : "
PATH=/root/xc/inst/bin:$PATH aarch64-pc-cygwin-g++ --version | head -1

echo
echo "############ autoload.cc: are remaining .align sites x86-only? ############"
awk 'NR>=60 && NR<=200 {
  if ($0 ~ /__x86_64__|__aarch64__|#else|#endif|\.align|\.balign|LoadDLLprime|define/) printf "%4d: %s\n", NR, $0
}' $L/runtime/winsup/cygwin/autoload.cc | head -40
