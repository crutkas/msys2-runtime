#!/bin/bash
echo "############ where does the conflicting decl come from? ############"
grep -rn 'feenableexcept' /root/xc/w-link/runtime/newlib/libc/include/ 2>/dev/null | head
echo "--- fenv.h include chain ---"
sed -n '1,25p' /root/xc/w-link/runtime/newlib/libc/include/fenv.h
echo
echo "--- machine/fenv.h for aarch64 ---"
find /root/xc/w-link/runtime/newlib/libc/machine/aarch64 -name 'fenv*' | while read f; do
  echo "== $f =="; grep -n 'feenableexcept\|fedisableexcept\|fegetexcept' "$f"
done
echo
echo "--- the exact conflicting line reported by gcc ---"
grep -rn 'feenableexcept' /root/xc/bld/newlib/targ-include/ 2>/dev/null | head
