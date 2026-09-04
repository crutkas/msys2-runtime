#!/bin/bash
echo "############ A. exception::handle / myfault ############"
grep -rn 'myfault\|::handle' /root/xc/runtime/winsup/cygwin/local_includes/exception.h | head -20
echo "--- definitions in exceptions.cc? ---"
grep -n 'exception::handle\|exception::myfault\|DISPATCHER_CONTEXT' /root/xc/runtime/winsup/cygwin/exceptions.cc | head -20
echo "--- is exceptions.o built and does it define them? ---"
export PATH=/root/xc/inst/bin:$PATH
aarch64-pc-cygwin-nm -C /root/xc/bld/winsup/cygwin/exceptions.o 2>/dev/null | grep -i 'handle\|myfault' | head -10

echo
echo "############ B. did libm/machine/aarch64 provide fma/fmaf? ############"
ls /root/xc/runtime/newlib/libm/machine/aarch64/ 2>&1
echo "--- fma/fmaf source anywhere in newlib ---"
find /root/xc/runtime/newlib -name 'fma.c' -o -name 'fmaf.c' -o -name 's_fma.c' 2>/dev/null | head
echo "--- are fma/fmaf in the libm.a we built? ---"
aarch64-pc-cygwin-nm /root/xc/bld/newlib/libm.a 2>/dev/null | grep -w 'T fma\|T fmaf' | head

echo
echo "############ C. _ctype_ in libc.a? ############"
aarch64-pc-cygwin-nm /root/xc/bld/newlib/libc.a 2>/dev/null | grep -w '_ctype_' | head -3

echo
echo "############ D. x86-only fenv/alloca exports in cygwin.din ############"
grep -n 'fegetprec\|fesetprec\|fegetexcept\|fedisableexcept\|_fe_nomask_env\|__alloca\|msys_dll_init' \
  /root/xc/runtime/winsup/cygwin/cygwin.din | head -20
