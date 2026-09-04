#!/bin/bash
export PATH=/root/xc/inst/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
echo "=== ld emulations (supported targets) ==="
aarch64-pc-cygwin-ld -V 2>&1 | head -20
echo
echo "=== as --version ==="
aarch64-pc-cygwin-as --version 2>&1 | head -3
echo
echo "=== objdump -i (bfd targets) ==="
aarch64-pc-cygwin-objdump -i 2>&1 | head -25
echo
echo "=== gcc -v ==="
aarch64-pc-cygwin-gcc -v 2>&1 | tail -5
echo
echo "=== include search path ==="
echo | aarch64-pc-cygwin-gcc -E -Wp,-v -x c - 2>&1 | head -20
echo
echo "=== sysroot dir listing ==="
ls -R /root/xc/inst/aarch64-pc-cygwin 2>&1 | head -60
echo
echo "=== can it assemble+link a trivial object? ==="
cd /root/xc/t 2>/dev/null || { mkdir -p /root/xc/t; cd /root/xc/t; }
printf 'int foo(int a){return a+1;}\n' > tiny.c
aarch64-pc-cygwin-gcc -c tiny.c -o tiny.o 2>&1 | head -10
echo "CC_EXIT=$?"
file tiny.o 2>&1
aarch64-pc-cygwin-objdump -h tiny.o 2>&1 | head -15
