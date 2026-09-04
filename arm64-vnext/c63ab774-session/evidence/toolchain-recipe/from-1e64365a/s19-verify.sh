#!/bin/bash
# DIAGNOSTIC-ONLY edits in the WSL scratch clone, to prove the remaining failures are
# source-side port gaps rather than toolchain gaps. This is NOT port work and is not
# intended to be kept; nothing here is committed anywhere.
export PATH=/root/xc/inst/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
S=/root/xc/runtime/winsup/cygwin
BLD=/root/xc/bld

# (1) target-detection: newlib's generic aarch64 MALLOC_ALIGNMENT vs Cygwin's
sed -i 's|^#define MALLOC_ALIGNMENT ((size_t)16U)$|#undef MALLOC_ALIGNMENT\n#define MALLOC_ALIGNMENT ((size_t)16U)|' $S/local_includes/cygmalloc.h
grep -n -A1 'undef MALLOC_ALIGNMENT' $S/local_includes/cygmalloc.h

# (2) target-detection: linker script has no aarch64 OUTPUT_FORMAT
python3 - <<'PY'
import re
p='/root/xc/runtime/winsup/cygwin/cygwin.sc.in'
s=open(p).read()
s=s.replace('''#else
#error unimplemented for this target
#endif''','''#elif defined(__aarch64__)
OUTPUT_FORMAT(pei-aarch64-little)
SEARCH_DIR("/usr/aarch64-pc-cygwin/lib/w32api"); SEARCH_DIR("=/usr/lib/w32api");
#else
#error unimplemented for this target
#endif''',1)
open(p,'w').write(s)
PY
sed -n '1,14p' $S/cygwin.sc.in

# (3) target-detection: fabsl has no aarch64 branch -> falls off the end
sed -i 's|^#elif defined(__arm__) \|\| defined(_ARM_)$|#elif defined(__arm__) \|\| defined(_ARM_) \|\| defined(__aarch64__)|' $S/math/fabsl.c
grep -n 'aarch64' $S/math/fabsl.c

cd $BLD/winsup/cygwin
INC=$(sed -n 's/^AM_CPPFLAGS = //p' Makefile | head -1)
find $BLD/winsup/cygwin -name '*.o' -delete
ulimit -u 4096
make -k -j12 INCLUDES="$INC" > /root/xc/winsup-build4.log 2>&1
echo "=========== RUN A: +3 target-detection fixes, -Werror still on ==========="
echo "objects: $(find $BLD/winsup/cygwin -name '*.o' | wc -l) / 310"
echo "errors:  $(grep -c 'error:' /root/xc/winsup-build4.log)"
grep -o 'error: .*' /root/xc/winsup-build4.log | sed 's/[0-9]\+/N/g' | sort | uniq -c | sort -rn

find $BLD/winsup/cygwin -name '*.o' -delete
make -k -j12 INCLUDES="$INC" CFLAGS="-g -O2 -Wno-error" CXXFLAGS="-g -O2 -Wno-error" > /root/xc/winsup-build5.log 2>&1
echo
echo "=========== RUN B: same, but warnings not fatal (isolates HARD errors) ==========="
echo "objects: $(find $BLD/winsup/cygwin -name '*.o' | wc -l) / 310"
echo "errors:  $(grep -c 'error:' /root/xc/winsup-build5.log)"
grep -o 'error: .*' /root/xc/winsup-build5.log | sed 's/[0-9]\+/N/g' | sort | uniq -c | sort -rn
echo "--- remaining failed targets ---"
grep -o '^make\[1\]: \*\*\* \[[^]]*\]' /root/xc/winsup-build5.log | sed 's/.*: \[//;s/\]//;s/^Makefile:[0-9]*: //' | sort -u
