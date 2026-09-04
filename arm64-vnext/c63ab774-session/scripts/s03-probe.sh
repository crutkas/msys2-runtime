#!/bin/bash
cd /root/xc/runtime/newlib || exit 1
echo "=== configure.host aarch64 blocks ==="
grep -n 'aarch64' configure.host
echo
echo "=== HAVE_LIBM_MACHINE_AARCH64 origin ==="
grep -rn 'HAVE_LIBM_MACHINE_AARCH64\|libm_machine_dir' libm/acinclude.m4 acinclude.m4 configure.ac 2>/dev/null | head -20
