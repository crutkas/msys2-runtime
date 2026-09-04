#!/bin/bash
# _my_tls sits at (StackBase - __CYGTLS_PADSIZE__) and extends UP to StackBase.
# If sizeof(_cygtls) exceeds 12800 on aarch64, every _my_tls access writes past
# the stack top. ARM64's CONTEXT is a different size from x86_64's, and _cygtls
# embeds one, so the pad may no longer be big enough.
set -u
export PATH=/root/xc/inst/bin:$PATH
L=/root/xc/w-link
R=$L/runtime/winsup/cygwin
B=$L/bld/winsup/cygwin

echo "############ is there any check that _cygtls fits the pad? ############"
grep -rn 'CYGTLS_PADSIZE' $R --include=*.cc --include=*.h --include=*.c | grep -v 'config.h:31'

echo
echo "############ measure sizeof(_cygtls) and sizeof(CONTEXT) for aarch64 ############"
INC=$(sed -n 's/^AM_CPPFLAGS = //p' $B/Makefile | head -1)
cat > /tmp/tlssize.cc <<'EOF'
#include "winsup.h"
#include "cygtls.h"
extern "C" const int probe_sizeof_cygtls  = (int) sizeof (_cygtls);
extern "C" const int probe_sizeof_context = (int) sizeof (CONTEXT);
extern "C" const int probe_padsize        = (int) __CYGTLS_PADSIZE__;
extern "C" const int probe_fits           = (int) (sizeof (_cygtls) <= __CYGTLS_PADSIZE__);
EOF
cd $B
aarch64-pc-cygwin-g++ -c -g -O2 -D__MSYS__ -Wno-error $INC \
  -I$R/include -I/root/xc/bld/newlib/targ-include -I$L/runtime/newlib/libc/include \
  /tmp/tlssize.cc -o /tmp/tlssize.o 2>&1 | head -10

if [ -f /tmp/tlssize.o ]; then
  echo "--- values ---"
  for s in probe_sizeof_cygtls probe_sizeof_context probe_padsize probe_fits; do
    off=$(aarch64-pc-cygwin-nm /tmp/tlssize.o | awk -v n="$s" '$3==n{print $1}')
    printf '  %-22s ' "$s"
    aarch64-pc-cygwin-objdump -s -j .rdata /tmp/tlssize.o 2>/dev/null | grep -A200 'Contents' >/dev/null
    python3 -B -c "
import subprocess,struct,sys
o='/tmp/tlssize.o'
nm=subprocess.run(['aarch64-pc-cygwin-nm','--print-file-name','-S',o],capture_output=True,text=True).stdout
" 2>/dev/null
    echo ""
  done
  echo "--- simpler: read them straight out with a static_assert probe ---"
fi

echo
echo "############ direct approach: force the compiler to print them ############"
cat > /tmp/tlssize2.cc <<'EOF'
#include "winsup.h"
#include "cygtls.h"
template <int N> struct SHOW;
SHOW<(int) sizeof (_cygtls)>  s1;
SHOW<(int) sizeof (CONTEXT)>  s2;
SHOW<(int) __CYGTLS_PADSIZE__> s3;
EOF
aarch64-pc-cygwin-g++ -c -g -O2 -D__MSYS__ -Wno-error $INC \
  -I$R/include -I/root/xc/bld/newlib/targ-include -I$L/runtime/newlib/libc/include \
  /tmp/tlssize2.cc -o /dev/null 2>&1 | grep -oE 'SHOW<[0-9]+>' | head -6
