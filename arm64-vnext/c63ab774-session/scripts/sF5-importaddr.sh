#!/bin/bash
R=/root/xc/w-link/runtime/winsup/cygwin
echo "############ import_address() -- the guard against self-recursion ############"
grep -rn -B6 -A40 'import_address' $R/mm/malloc_wrapper.cc $R/*.cc $R/local_includes/*.h 2>/dev/null \
  | grep -v '^--$' | head -60
