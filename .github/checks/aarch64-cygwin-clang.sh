#!/usr/bin/env sh
set -eu

: "${MVP_CLANG_PREFIX:?MVP_CLANG_PREFIX is required}"
: "${MVP_RUNTIME_SOURCE:?MVP_RUNTIME_SOURCE is required}"
: "${MVP_RUNTIME_BUILD:?MVP_RUNTIME_BUILD is required}"
: "${MVP_CRT_PREFIX:?MVP_CRT_PREFIX is required}"
: "${MVP_CLANG_RESOURCE_DIR:?MVP_CLANG_RESOURCE_DIR is required}"

compiler=clang.exe
case "${MVP_CXX:-0}" in
  1) compiler=clang++.exe ;;
esac

for argument
do
  if [ "$argument" = "-dumpmachine" ]; then
    echo aarch64-pc-cygwin
    exit 0
  fi
done

driver="-target aarch64-w64-windows-gnu -nostdinc
  -U__MINGW32__ -U__MINGW64__ -D__CYGWIN__ -D__MSYS__
  -D__WINT_TYPE__=unsigned -fcommon -Wno-macro-redefined"
includes="-I${MVP_RUNTIME_SOURCE}/winsup/cygwin/include
  -I${MVP_RUNTIME_BUILD}/aarch64-pc-cygwin/newlib/targ-include
  -I${MVP_RUNTIME_SOURCE}/newlib/libc/include
  -isystem ${MVP_CLANG_RESOURCE_DIR}/include
  -idirafter ${MVP_CRT_PREFIX}/include"

for argument
do
  case "$argument" in
    -c|-E|-S|-M|-MM)
      exec "${MVP_CLANG_PREFIX}/${compiler}" $driver "$@" $includes
      ;;
  esac
done

cygwin_build="${MVP_RUNTIME_BUILD}/aarch64-pc-cygwin/winsup/cygwin"
exec "${MVP_CLANG_PREFIX}/${compiler}" $driver "$@" $includes \
  -fuse-ld=lld -nostdlib \
  -Wl,--subsystem,console -Wl,--entry,mainCRTStartup \
  -Wl,--dynamicbase -Wl,--disable-high-entropy-va -Wl,--enable-reloc-section \
  -L"$cygwin_build" -L"${MVP_CRT_PREFIX}/lib" \
  -L"${MVP_CLANG_RESOURCE_DIR}/lib/windows" \
  "$cygwin_build/crt0.o" "$cygwin_build/libmsys-2.0.a" \
  -lclang_rt.builtins-aarch64 -luser32 -lkernel32 -lntdll
