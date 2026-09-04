#!/bin/bash
# Where does __MSYS__ come from, and can the toolchain target *-pc-msys?
export PATH=/root/xc/inst/bin:$PATH
G=/root/xc/gcc-src

echo "############ 1. does GCC define __MSYS__ anywhere? ############"
grep -rn '__MSYS__' $G/gcc/config/ 2>/dev/null | head -10
echo "--- msys in gcc/config.gcc ---"
grep -n 'msys' $G/gcc/config.gcc | head -20

echo
echo "############ 2. does config.sub accept aarch64-pc-msys? ############"
for t in aarch64-pc-msys x86_64-pc-msys aarch64-pc-cygwin; do
  printf '  %-22s -> %s\n' "$t" "$($G/config.sub $t 2>&1)"
done

echo
echo "############ 3. does OUR compiler define __MSYS__ / __CYGWIN__? ############"
echo | aarch64-pc-cygwin-gcc -dM -E - 2>/dev/null | grep -iE '__MSYS__|__CYGWIN__|__CYGWIN32__|WIN32|unix' | sort

echo
echo "############ 4. what does the x86_64 msys2 world use? (msys-flavour markers) ############"
grep -rn 'MSYS' $G/gcc/config.gcc | head -10
echo "--- binutils support ---"
grep -rn 'msys' /root/xc/gcc-src/config.sub 2>/dev/null | head -5

echo
echo "############ 5. is __MSYS__ perhaps set in the runtime's own build flags? ############"
grep -rn 'D__MSYS__\|__MSYS__' /root/xc/w-link/runtime/winsup/Makefile.am /root/xc/w-link/runtime/winsup/cygwin/Makefile.am /root/xc/w-link/runtime/Makefile.am.common 2>/dev/null | head
grep -rn '__MSYS__' /root/xc/w-link/bld/winsup/cygwin/Makefile | head -5
