#!/bin/bash
# DIAGNOSTIC (clearly labelled, scratch-only, in /root/xc/w-link only):
#
# ROOT CAUSE, measured: IMAGE_IMPORT_DESCRIPTOR is 20 bytes (5 LONGs) and
# cygwin.sc emits .idata$2/$3 + a 20-byte null terminator back-to-back with no
# alignment, so .idata$4 begins at 0x...a03c (60 == 4 mod 8) and every .idata$5
# thunk lands 4-mod-8 (e.g. __imp_RtlCaptureContext at 0x18036b1ac).
#
# On x86-64 this is invisible: RIP-relative `mov` has no alignment constraint.
# On AArch64 `ldr x3,[x3]` carries IMAGE_REL_ARM64_PAGEOFFSET_12L, whose imm12 is
# SCALED BY 8 for a 64-bit load, so the target MUST be 8-byte aligned -> otherwise
# "relocation truncated to fit".
#
# Minimal correct fix: align the IAT/ILT to 8 bytes on aarch64.
set -u
L=/root/xc/w-link
SC=$L/runtime/winsup/cygwin/cygwin.sc.in

cp -p $SC $SC.bak

python3 -B - <<'PY'
import io
p = "/root/xc/w-link/runtime/winsup/cygwin/cygwin.sc.in"
s = io.open(p, encoding="utf-8", newline="").read()
if "__aarch64_idata_align__" in s:
    print("already patched"); raise SystemExit
old = """    SORT(*)(.idata$4)
    SORT(*)(.idata$5)"""
new = """#ifdef __aarch64__
    /* __aarch64_idata_align__ : IMAGE_IMPORT_DESCRIPTOR is 20 bytes, so the IAT
       would otherwise start 4-mod-8.  AArch64 IMAGE_REL_ARM64_PAGEOFFSET_12L on
       a 64-bit LDR scales imm12 by 8 and requires an 8-byte-aligned target.  */
    . = ALIGN(8);
#endif
    SORT(*)(.idata$4)
#ifdef __aarch64__
    . = ALIGN(8);
#endif
    SORT(*)(.idata$5)"""
assert old in s, "idata block not found verbatim"
io.open(p, "w", encoding="utf-8", newline="").write(s.replace(old, new, 1))
print("patched cygwin.sc.in with aarch64 .idata 8-byte alignment")
PY

echo
echo "=== regenerate cygwin.sc ==="
cd $L/bld/winsup/cygwin
export PATH=/root/xc/inst/bin:$PATH
rm -f cygwin.sc
aarch64-pc-cygwin-gcc -E - -P < $SC -o cygwin.sc
echo "cygwin.sc: $(stat -c%s cygwin.sc) bytes (was 3729)"
grep -n -A10 '\.idata ALIGN' cygwin.sc
