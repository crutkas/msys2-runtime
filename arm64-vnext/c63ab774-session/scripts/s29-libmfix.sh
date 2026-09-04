#!/bin/bash
# CORRECTION of my own earlier over-broad change.
#
# Earlier I set libm_machine_dir='' to stop libm/Makefile.inc pulling in ld128/.
# That was too blunt: it ALSO dropped libm/machine/aarch64/, which legitimately
# provides s_fma.c, sf_fma.c, the whole fenv family and optimised rounding.
#
# Correct behaviour: KEEP libm/machine/aarch64, EXCLUDE ld128 (and ld), because
# aarch64-pc-cygwin has _LDBL_EQ_DBL=1 (long double == double, 64-bit) whereas
# ld128 assumes LDBL_MANT_DIG==113. libm/Makefile.inc ties them together, which
# is the actual newlib bug.  Here we emulate the correct conditional by
# commenting the ld128 object-list entries out of the generated Makefile.
set -e
SRC=/root/xc/runtime/newlib
BLD=/root/xc/bld/newlib
export PATH=/root/xc/inst/bin:$PATH

# 1. restore libm_machine_dir=aarch64
sed -i "s/^\tlibm_machine_dir=$/\tlibm_machine_dir=aarch64/" "$SRC/configure.host"
grep -n -A3 'aarch64\*)' "$SRC/configure.host" | head -6

# 2. reconfigure with _fpmath.h hidden (keeps libm/ld out; that dir assumes an
#    80- or 128-bit long double and #errors otherwise)
CFGLINE=$(grep -m1 '^  \$ .*configure' "$BLD/config.log" | sed 's/^  \$ //')
FPM="$SRC/libc/machine/aarch64/machine/_fpmath.h"
mv "$FPM" "$FPM.hidden"
cd "$BLD"
set +e
eval "$CFGLINE" > cfg3.log 2>&1; RC=$?
set -e
mv "$FPM.hidden" "$FPM"
echo "CONFIGURE EXIT $RC"

# 3. comment ld128 objects out of the object list only (leave inert rules alone)
python3 -B - <<'PY'
import io, re
p = "/root/xc/bld/newlib/Makefile"
s = io.open(p, encoding="utf-8", newline="").read().split("\n")
out, n = [], 0
for ln in s:
    if re.match(r"^\s*libm/ld128/libm_a-\S+\.\$\(OBJEXT\)\s*\\?\s*$", ln):
        out.append("#" + ln); n += 1
    else:
        out.append(ln)
io.open(p, "w", encoding="utf-8", newline="").write("\n".join(out))
print("commented-out ld128 object entries:", n)
PY

echo "=== rebuild newlib ==="
timeout 2400 make -j12 > /root/xc/newlib-build3.log 2>&1
echo "MAKE EXIT $?"
grep 'Error\|error:' /root/xc/newlib-build3.log | head -10
ls -la $BLD/libc.a $BLD/libm.a
echo "=== fma / fmaf now present? ==="
aarch64-pc-cygwin-nm $BLD/libm.a 2>/dev/null | grep -wE 'T fma|T fmaf' | head
echo "=== fenv family present? ==="
aarch64-pc-cygwin-nm $BLD/libm.a 2>/dev/null | grep -wE 'T feclearexcept|T fegetround|T fesetround' | head
