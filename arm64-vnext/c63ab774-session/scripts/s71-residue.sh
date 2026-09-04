#!/bin/bash
export PATH=/root/xc/inst/bin:$PATH
L=/root/xc/w-link
R=$L/runtime/winsup/cygwin
echo "############ reloc truncations after the alignment fix ############"
grep -c 'relocation truncated' /root/xc/link-combined.log

echo
echo "############ msys_dll_init / msys_detach_dll ############"
grep -n 'msys_dll_init\|msys_detach_dll' $R/dcrt0.cc | head -10
echo "--- are they inside an arch guard? ---"
awk '/msys_dll_init|msys_detach_dll/{print NR": "$0}' $R/dcrt0.cc | head
echo "--- surrounding ifdefs in dcrt0.cc ---"
grep -n '__x86_64__\|__aarch64__\|#ifdef\|#endif' $R/dcrt0.cc | awk -F: '$1>1' | head -20
echo "--- does dcrt0.o define them? ---"
aarch64-pc-cygwin-nm $L/bld/winsup/cygwin/dcrt0.o 2>/dev/null | grep -i 'msys_'

echo
echo "############ fenv family: where defined on x86_64? ############"
for s in feenableexcept fedisableexcept fegetexcept fegetprec fesetprec _fe_nomask_env; do
  printf '  %-18s : ' "$s"
  grep -rl "\b$s\b" /root/xc/runtime/newlib/libm /root/xc/runtime/newlib/libc 2>/dev/null | head -2 | tr '\n' ' '
  echo
done

echo
echo "############ are they in the aarch64 fenv? ############"
ls /root/xc/runtime/newlib/libm/machine/aarch64/fenv.c >/dev/null 2>&1 && \
  grep -n '^[a-z_]*(' /root/xc/runtime/newlib/libm/machine/aarch64/fenv.c | head -20

echo
echo "############ _ctype_ and __alloca ############"
printf '  _ctype_ in libc.a : '; aarch64-pc-cygwin-nm /root/xc/bld/newlib/libc.a 2>/dev/null | grep -cw '_ctype_'
printf '  __alloca sources  : '; grep -rl '__alloca' $R --include=*.cc --include=*.c --include=*.S 2>/dev/null | head -3 | tr '\n' ' '; echo

echo
echo "############ how does cygwin.din export these? ############"
grep -n '^\s*\(__alloca\|_ctype_\|_fe_nomask_env\|fedisableexcept\|feenableexcept\|fegetexcept\|fegetprec\|fesetprec\|msys_dll_init\|msys_detach_dll\)\b' $R/cygwin.din
