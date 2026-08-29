#!/bin/sh

set -eu

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
math="$repo_root/winsup/cygwin/math"

command -v awk >/dev/null

if grep -R -n -E 'defined[[:space:]]*\(_x86_64__\)|_defined[[:space:]]*\(__aarch64__\)' \
     "$math"
then
  echo "invalid architecture preprocessor spelling found" >&2
  exit 1
fi

for wrapper in cosl_internal.S exp2l.S frexpl.S ilogbl.S internal_logl.S \
  log10l.S log1pl.S log2l.S remainderl.S remquol.S sinl_internal.S tanl.S
do
  if awk '
    /#elif.*(__aarch64__|__SIZEOF_LONG_DOUBLE__)/ { arm = 1; next }
    arm && /^#(elif|else|endif)/ { arm = 0 }
    arm && /^[[:space:]]*bl[[:space:]]/ { found = 1 }
    END { exit found ? 0 : 1 }
  ' "$math/$wrapper"
  then
    echo "$wrapper contains bl in its AArch64 tail-wrapper branch" >&2
    exit 1
  fi
done

grep -Eq 'scvtf[[:space:]]+d1,[[:space:]]*w0' "$math/scalbnl.S"
grep -Eq 'fmov[[:space:]]+d0,[[:space:]]*#2\.0' "$math/scalbnl.S"
grep -Eq 'str[[:space:]]+d0,[[:space:]]*\[sp,[[:space:]]*#16\]' \
  "$math/scalbnl.S"
grep -Eq 'str[[:space:]]+w0,[[:space:]]*\[sp,[[:space:]]*#24\]' \
  "$math/scalbnl.S"
grep -Eq 'stp[[:space:]]+x29,[[:space:]]*x30' "$math/scalbnl.S"
grep -Eq 'ldp[[:space:]]+x29,[[:space:]]*x30' "$math/scalbnl.S"
grep -Eq 'fcmp[[:space:]]+d1,[[:space:]]*d1' "$math/scalbl.S"
grep -Eq 'frintz[[:space:]]+d2,[[:space:]]*d1' "$math/scalbl.S"

grep -Fq 'aarch64-*-msys*)' "$repo_root/newlib/configure"
grep -Fq 'aarch64-*-msys*)' "$repo_root/newlib/libc/acinclude.m4"
grep -Fq '#if defined(__x86_64__)' "$math/expm1.def.h"
grep -Fq 'x = expm1 ((double) x);' "$math/expm1.def.h"
grep -Fq 'return context->Pc;' "$repo_root/winsup/utils/profiler.cc"
grep -Fq 'IMAGE_FILE_MACHINE_ARM64' "$repo_root/winsup/utils/profiler.cc"
grep -Fq 'bfd_arch_aarch64' "$repo_root/winsup/utils/dumper.cc"
grep -Fq '#define SW_BREAKPOINT_SIZE 4' "$repo_root/winsup/utils/ssp.c"
grep -Fq 'FlushInstructionCache' "$repo_root/winsup/utils/ssp.c"
if grep -n 'error %lu' "$repo_root/winsup/utils/ssp.c"
then
  echo "SSP Windows error diagnostics must match the 32-bit DWORD type" >&2
  exit 1
fi
grep -Fq '#define ARCH_STR  "&arch=aarch64"' \
  "$repo_root/winsup/utils/mingw/cygcheck.cc"

echo "Layer-5 static architecture and control-flow checks passed."
