#!/bin/sh

set -eu

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
work=${RUNNER_TEMP:-/tmp}/aarch64-layer5.$$
cc=${CC:-clang}
cxx=${CXX:-clang++}
readobj=${LLVM_READOBJ:-llvm-readobj}
objdump=${LLVM_OBJDUMP:-llvm-objdump}
nm=${LLVM_NM:-llvm-nm}

cleanup()
{
  rm -rf "$work"
}
trap cleanup EXIT HUP INT TERM
mkdir -p "$work"

case "$("$cc" -dumpmachine)" in
aarch64-*-windows-* | aarch64-*-mingw*) ;;
*)
  echo "compiler is not targeting native Windows ARM64" >&2
  exit 1
  ;;
esac

cflags="-target aarch64-w64-windows-gnu -O2 -Wall -Wextra -Werror \
  -Wno-unknown-warning-option -fno-builtin"

math_sources="
acoshl.c acosl.c asinhl.c asinl.c atan2l.c atanhl.c atanl.c cosl_internal.S
cossin.c exp2l.S expl.c expm1l.c
fabsl.c fmodl.c frexpl.S ilogbl.S internal_logl.S ldexpl.c lgammal.c
log10l.S log1pl.S log2l.S logbl.c lrintl.c nextafterl.c remainder.S
remainderf.S remainderl.S remquol.S rintl.c scalbl.S scalbnl.S
sinl_internal.S tanl.S truncl.c
"
for source in $math_sources
do
  object="$work/${source%.*}.o"
  "$cc" $cflags -c "$repo_root/winsup/cygwin/math/$source" -o "$object"
done

if "$nm" "$work/remainder.o" | grep -Eq '[[:space:]]remainder$'
then
  echo "AArch64 remainder.S must not shadow the double implementation" >&2
  exit 1
fi
if "$nm" "$work/remainderf.o" | grep -Eq '[[:space:]]remainderf$'
then
  echo "AArch64 remainderf.S must not emit an empty public symbol" >&2
  exit 1
fi

for wrapper in cosl_internal exp2l frexpl ilogbl internal_logl log10l \
  log1pl log2l remainderl remquol sinl_internal tanl
do
  "$objdump" -dr "$work/$wrapper.o" >"$work/$wrapper.dis"
  grep -q 'IMAGE_REL_ARM64_BRANCH26' "$work/$wrapper.dis"
done

"$cc" $cflags -D_WIN32_WINNT=0x0a00 \
  "$repo_root/.github/checks/aarch64-layer5-math.c" \
  "$work/acoshl.o" "$work/acosl.o" "$work/asinhl.o" "$work/atan2l.o" \
  "$work/atanhl.o" "$work/cosl_internal.o" \
  "$work/exp2l.o" "$work/expl.o" "$work/expm1l.o" "$work/fabsl.o" \
  "$work/frexpl.o" "$work/ilogbl.o" "$work/log10l.o" "$work/log1pl.o" \
  "$work/log2l.o" "$work/remainderl.o" "$work/remquol.o" \
  "$work/scalbl.o" "$work/scalbnl.o" "$work/sinl_internal.o" \
  "$work/tanl.o" -o "$work/layer5-math.exe"

"$cc" $cflags -D_WIN32_WINNT=0x0a00 \
  '-Dprogram_invocation_short_name=__argv[0]' \
  -idirafter "$repo_root/winsup/cygwin/include" \
  "$repo_root/winsup/utils/ssp.c" -o "$work/ssp.exe"

"$cxx" $cflags -include windows.h \
  -DS_IRUSR=0400 -DS_IWUSR=0200 -DS_IRGRP=0040 -DS_IROTH=0004 \
  -I"$repo_root/winsup/utils" \
  -idirafter "$repo_root/winsup/cygwin/local_includes" \
  -idirafter "$repo_root/winsup/cygwin/include" \
  -c "$repo_root/winsup/utils/profiler.cc" -o "$work/profiler.o"

"$cxx" $cflags -Wno-unused-parameter -Wno-missing-field-initializers \
  -fno-exceptions -fno-rtti -fno-use-cxa-atexit \
  -D_WIN32_WINNT=0x0a00 \
  -I"$repo_root/winsup/utils" -I"$repo_root/winsup/utils/mingw" \
  -idirafter "$repo_root/winsup/cygwin/include" \
  -c "$repo_root/winsup/utils/mingw/cygcheck.cc" -o "$work/cygcheck.o"

for artifact in "$work"/*.o "$work"/*.exe
do
  "$readobj" --file-headers "$artifact" |
    grep -q 'Machine: IMAGE_FILE_MACHINE_ARM64 (0xAA64)'
done
for image in "$work"/*.exe
do
  "$readobj" --file-headers "$image" |
    grep -q 'IMAGE_FILE_EXECUTABLE_IMAGE'
done

if test "${LAYER5_COMPILE_ONLY:-0}" = 1
then
  echo "ARM64 production layer-5 paths compiled and linked."
  exit 0
fi

"$work/layer5-math.exe"
"$work/ssp.exe" --help >/dev/null

printf '%s\n' \
  "Native ARM64 layer-5 validation passed:" \
  "  production long-double math objects compiled as AA64 COFF" \
  "  production math executed across values, quadrants, exponents, and errors" \
  "  production SSP linked and executed; profiler and cygcheck compiled" \
  "  process, PE/COFF, tail-call, and empty-symbol invariants verified"
