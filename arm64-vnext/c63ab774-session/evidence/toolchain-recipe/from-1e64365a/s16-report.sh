#!/bin/bash
L=/root/xc/winsup-build3.log
echo "=========== FAILED TARGETS ==========="
grep -o '^make\[1\]: \*\*\* \[[^]]*\]' $L | sed 's/.*: \[//;s/\]//' | sed 's/^Makefile:[0-9]*: //' | sort -u
echo
echo "=========== MISSING aarch64 ASM SOURCES ==========="
grep -o "No rule to make target '[^']*'" $L | sort -u
echo
echo "=========== EVERY ERROR WITH FILE:LINE ==========="
grep -n 'error:' $L | sed 's/^[0-9]*://' | sort -u
echo
echo "=========== #error unimplemented context ==========="
grep -n -B6 '#error unimplemented' $L | head -20
echo
echo "=========== long double constant context ==========="
grep -n -B4 "exceeds range of 'long double'" $L | head -20
echo
echo "=========== MALLOC_ALIGNMENT context ==========="
grep -n -B6 "MALLOC_ALIGNMENT' redefined" $L | head -14
echo
echo "=========== TOTAL SOURCES vs BUILT ==========="
echo "expected .o in Makefile: $(grep -o '[a-zA-Z0-9_/]*\.o' /root/xc/bld/winsup/cygwin/Makefile | sort -u | wc -l)"
echo "built .o: $(find /root/xc/bld/winsup/cygwin -name '*.o' | wc -l)"
echo
echo "=========== CONFIRM: do the ARM64-port-touched files compile? ==========="
for f in exceptions cygtls thread fork dcrt0 profil create_posix_thread autoload; do
  if [ -f /root/xc/bld/winsup/cygwin/$f.o ]; then echo "  OK   $f.o"; else echo "  FAIL $f.o"; fi
done
