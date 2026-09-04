#!/bin/bash
# Two hardening items from the sibling defects audit (57224227).
# Both are LATENT, not the crash: unwind works today via orphan placement, and
# _WIN64 is defined today so the 64-bit pseudo-reloc cases survive. Making both
# explicit so neither depends on something that could silently change.
set -u
R=/root/xc/w-link/runtime/winsup/cygwin
cd $R || exit 1

cp cygwin.sc.in /tmp/cygwin.sc.in.bak
cp pseudo-reloc.cc /tmp/pseudo-reloc.cc.bak

# 1. .xdata output-section placement -- explicit rather than relying on the
#    linker's orphan-section heuristic happening to put it before .pdata.
python3 -B - <<'PY'
import re
p='/root/xc/w-link/runtime/winsup/cygwin/cygwin.sc.in'
s=open(p).read()
old="""#ifdef __x86_64__
  .xdata ALIGN(__section_alignment__) :
  {
    *(.xdata*)
  }
#endif"""
new="""#if defined(__x86_64__) || defined(__aarch64__)
  .xdata ALIGN(__section_alignment__) :
  {
    *(.xdata*)
  }
#endif"""
assert s.count(old)==1, "xdata block not found exactly once"
open(p,'w').write(s.replace(old,new))
print("cygwin.sc.in: .xdata placement now explicit for aarch64")
PY

# 2. pseudo-reloc 64-bit cases -- currently reached only because the w32api
#    _cygwin.h fix defines _WIN64. Name the architecture directly so the 64-bit
#    path cannot silently fall to the "unknown bit size" default.
python3 -B - <<'PY'
p='/root/xc/w-link/runtime/winsup/cygwin/pseudo-reloc.cc'
s=open(p).read()
old='#if defined (__x86_64__) || defined (_WIN64)'
new='#if defined (__x86_64__) || defined (__aarch64__) || defined (_WIN64)'
n=s.count(old)
assert n==3, f"expected 3 guards, found {n}"
open(p,'w').write(s.replace(old,new))
print(f"pseudo-reloc.cc: {n} guards now name __aarch64__ directly")
PY

echo
echo "=== verify ==="
sed -n '82p' cygwin.sc.in
grep -c 'defined (__aarch64__)' pseudo-reloc.cc
