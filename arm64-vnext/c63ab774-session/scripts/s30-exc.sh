#!/bin/bash
export PATH=/root/xc/inst/bin:$PATH
echo "############ symbols exceptions.o actually defines ############"
aarch64-pc-cygwin-nm /root/xc/bld/winsup/cygwin/exceptions.o | grep -E ' T | t ' | grep -i 'exception' | head -20
echo
echo "############ does ANY object define exception::handle? ############"
cd /root/xc/bld/winsup/cygwin
for f in $(find . -name '*.o'); do
  if aarch64-pc-cygwin-nm "$f" 2>/dev/null | grep -q 'T _ZN9exception6handleE'; then echo "DEFINED IN: $f"; fi
done
echo "(no line above == nowhere defined)"
echo
echo "############ who REFERENCES it ############"
for f in $(find . -name '*.o'); do
  if aarch64-pc-cygwin-nm "$f" 2>/dev/null | grep -q 'U _ZN9exception6handleE'; then echo "REF IN: $f"; fi
done
echo
echo "############ exception.h declaration ############"
sed -n '1,60p' /root/xc/runtime/winsup/cygwin/local_includes/exception.h
