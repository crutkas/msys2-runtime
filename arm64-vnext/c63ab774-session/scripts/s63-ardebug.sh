#!/bin/bash
export PATH=/root/xc/inst/bin:$PATH
L=/root/xc/w-link
cd $L/bld/winsup/cygwin || exit 1
echo "=== how many objects in the have-list? ==="
wc -l < /tmp/objs_have.txt
echo "=== are those .o files actually valid? spot-check ==="
for o in devices.o dir.o errno.o fenv.o sigfe.o autoload.o; do
  printf '%-14s %10s bytes   ' "$o" "$(stat -c%s $o 2>/dev/null)"
  aarch64-pc-cygwin-objdump -f "$o" 2>&1 | sed -n '2p'
done

echo
echo "=== is 'ar' being confused by an EXISTING libdll.a? ==="
ls -la libdll.a 2>&1
rm -f libdll.a
echo "removed."

echo
echo "=== build the archive in ONE invocation via a response file ==="
aarch64-pc-cygwin-ar cr libdll.a @/tmp/objs_have.txt 2>&1 | head -5
echo "rc=$?"
ls -la libdll.a 2>&1

echo
echo "=== if that failed, try plain expansion ==="
if [ ! -s libdll.a ] || [ "$(stat -c%s libdll.a)" -lt 1000 ]; then
  rm -f libdll.a
  aarch64-pc-cygwin-ar cr libdll.a $(cat /tmp/objs_have.txt) 2>&1 | head -5
  echo "rc=$?"
  ls -la libdll.a 2>&1
fi

echo
echo "=== members + sigfe.o present? ==="
aarch64-pc-cygwin-ar t libdll.a 2>/dev/null | wc -l
aarch64-pc-cygwin-ar t libdll.a 2>/dev/null | grep -c '^sigfe.o$'
