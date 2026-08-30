#!/bin/sh

set -eu

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
work_root=$(cygpath -u "${RUNNER_TEMP:-/tmp}")
work="$work_root/aarch64-layer4-path-build"
clang_root=/clangarm64/bin
clang="$clang_root/clang.exe"
clangxx="$clang_root/clang++.exe"
readobj="$clang_root/llvm-readobj.exe"
w32api_root=$(cygpath -m /usr/include)
commit=${GITHUB_SHA:-0000000000000000000000000000000000000000}

cleanup()
{
  rm -rf "$work"
}
trap cleanup EXIT HUP INT TERM

rm -rf "$work"
mkdir -p "$work/winsup" "$work/newlib/targ-include"

(
  cd "$repo_root/winsup"
  ./autogen.sh
)

(
  cd "$work/winsup"
  ac_cv_lib_sframe_sframe_decode=no \
  ac_cv_lib_zstd_ZSTD_isError=no \
  CC="$clang -target aarch64-pc-cygwin" \
  CXX="$clangxx -target aarch64-pc-cygwin" \
  CPPFLAGS="-isystem $w32api_root -isystem $w32api_root/w32api -D__CYGWIN__ -D__MSYS__" \
  CXXFLAGS="-O2 -fdeclspec \
    -Wno-error=ignored-optimization-argument \
    -Wno-error=unknown-warning-option \
    -Wno-error=mismatched-tags \
    -Wno-error=nontrivial-memcall \
    -Wno-error=vla-cxx-extension \
    -Wno-error=gnu-designator" \
  AR="$clang_root/llvm-ar.exe" \
  AS="$clang" \
  DLLTOOL="$clang_root/llvm-dlltool.exe" \
  LD="$clang_root/ld.lld.exe" \
  NM="$clang_root/llvm-nm.exe" \
  OBJCOPY="$clang_root/llvm-objcopy.exe" \
  OBJDUMP="$clang_root/llvm-objdump.exe" \
  RANLIB="$clang_root/llvm-ranlib.exe" \
  STRIP="$clang_root/llvm-strip.exe" \
  WINDRES="$clang_root/llvm-windres.exe" \
    "$repo_root/winsup/configure" \
      --target=aarch64-pc-cygwin \
      --with-cross-bootstrap \
      --disable-doc \
      --disable-dependency-tracking \
      --with-msys2-runtime-commit="$commit"
)

build_log="$work/path-build.log"
if ! make -C "$work/winsup/cygwin" V=1 globals.h path.o \
     >"$build_log" 2>&1
then
  cat "$build_log"
  exit 1
fi
cat "$build_log"

grep -q -- '-Wall' "$build_log"
grep -q -- '-Werror' "$build_log"
grep -Eq -- '-Wimplicit-fallthrough(=5)?([[:space:]]|$)' "$build_log"
grep -q -- '-fno-rtti' "$build_log"
grep -q -- '/path.cc' "$build_log"
if grep -Eq -- '-Wno(-error=)?unused-function' "$build_log"
then
  echo 'unused-function diagnostics must remain fatal' >&2
  exit 1
fi

"$readobj" --file-headers "$work/winsup/cygwin/path.o" |
  grep -q 'Machine: IMAGE_FILE_MACHINE_ARM64 (0xAA64)'

echo 'Configured production path.cc object passed native ARM64 -Wall/-Werror compilation.'
